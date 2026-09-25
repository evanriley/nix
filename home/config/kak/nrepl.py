#!/usr/bin/env python3
"""nREPL client for Kakoune.

One daemon per project root keeps the nREPL connection and session alive. Kakoune talks
to it through this script (one process per keypress), and the daemon pushes results back
with `kak -p` as ready-to-run Kakoune commands.
"""
import errno
import fcntl
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

NREPL_VERSION = '1.7.0'
CIDER_NREPL_VERSION = '0.62.2'

CONNECT_TIMEOUT = 5.0
DAEMON_START_TIMEOUT = 15.0
REQUEST_TIMEOUT = 600.0
REPLY_MARGIN = 5.0
SYNC_TIMEOUT = 10.0
QUERY_TIMEOUT = 20.0
TEST_TIMEOUT = 900.0
COMPLETE_TIMEOUT = 2.0
JACK_IN_TIMEOUT = 300.0
INLINE_WIDTH = 80
INFO_LINES = 30
LOG_SEPARATOR = '; ' + '-' * 60
ROOT_MARKERS = ['.nrepl-port', 'deps.edn', 'bb.edn', 'shadow-cljs.edn', 'project.clj', '.git']


def quote(text):
    return "'" + str(text).replace("'", "''") + "'"


def markup_escape(text):
    return str(text).replace('\\', '\\\\').replace('{', '\\{')


def one_line(text):
    return ' '.join(str(text).split())


def root_for(filename, markers):
    start = Path(filename).absolute().parent if filename else Path.cwd()
    for directory in (start, *start.parents):
        if any(glob.glob(str(directory / marker)) for marker in markers):
            return directory
    return start


def project_root(filename):
    return root_for(filename, ROOT_MARKERS)


class BencodeIncomplete(Exception):
    pass


def bencode(value):
    if isinstance(value, bool):
        raise ValueError('cannot bencode a boolean; expected an int, str, bytes, list or dict')
    if isinstance(value, int):
        return b'i' + str(value).encode() + b'e'
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, (bytes, bytearray)):
        return str(len(value)).encode() + b':' + bytes(value)
    if isinstance(value, (list, tuple)):
        return b'l' + b''.join(map(bencode, value)) + b'e'
    if isinstance(value, dict):
        items = sorted(value.items(), key=lambda item: str(item[0]))
        return b'd' + b''.join(bencode(str(k)) + bencode(v) for k, v in items) + b'e'
    raise ValueError(f'cannot bencode {type(value).__name__}')


def bdecode_value(data, position):
    marker = data[position:position + 1]
    if not marker:
        raise BencodeIncomplete()
    if marker == b'i':
        end = data.find(b'e', position)
        if end < 0:
            raise BencodeIncomplete()
        return int(data[position + 1:end]), end + 1
    if marker in (b'l', b'd'):
        items, position = [], position + 1
        while True:
            head = data[position:position + 1]
            if not head:
                raise BencodeIncomplete()
            if head == b'e':
                position += 1
                break
            item, position = bdecode_value(data, position)
            items.append(item)
        if marker == b'l':
            return items, position
        return dict(zip(items[::2], items[1::2])), position
    if marker.isdigit():
        colon = data.find(b':', position)
        if colon < 0:
            raise BencodeIncomplete()
        end = colon + 1 + int(data[position:colon])
        if len(data) < end:
            raise BencodeIncomplete()
        return data[colon + 1:end].decode('utf-8', 'replace'), end
    raise ValueError(f'invalid bencode marker {marker!r} at offset {position}')


def bdecode(data):
    values, position = [], 0
    while position < len(data):
        try:
            value, position = bdecode_value(data, position)
        except BencodeIncomplete:
            break
        values.append(value)
    return values, data[position:]


OPENERS = b'([{'
CLOSERS = b')]}'
SYMBOL_BREAK = frozenset(b' \t\r\n\f()[]{}",;`~@^\\')
SYMBOL_PREFIX = b"#'"
NS_FORM = re.compile(rb'^\s*\(ns\s+(?:\^\S+\s+)*([^\s()\[\]{}]+)', re.M)
TEST_DEFINER = re.compile(
    r'\s*\(\s*(?:[^\s()\[\]{}/]+/)?(?:deftest|defspec)\s+(?:\^\S+\s+)*([^\s()\[\]{},"]+)')


def bracket_ranges(data):
    ranges, stack, index, size = [], [], 0, len(data)
    while index < size:
        byte = data[index:index + 1]
        if byte == b'\\':
            index += 2
        elif byte == b'"':
            index += 1
            while index < size:
                if data[index:index + 1] == b'\\':
                    index += 2
                    continue
                index += 1
                if data[index - 1:index] == b'"':
                    break
        elif byte == b';':
            newline = data.find(b'\n', index)
            index = size if newline < 0 else newline
        elif byte in OPENERS:
            stack.append(index)
            index += 1
        elif byte in CLOSERS:
            if stack:
                ranges.append((stack.pop(), index))
            index += 1
        else:
            index += 1
    ranges.extend((start, size - 1) for start in stack)
    return ranges


def form_range(data, offset, outermost):
    enclosing = [span for span in bracket_ranges(data) if span[0] <= offset <= span[1]]
    if not enclosing:
        return None
    start, end = min(enclosing) if outermost else max(enclosing)
    # Reader prefixes belong to the form: #{}, #(), #?(), '(), `(), @(...)
    while start > 0 and data[start - 1:start] in (b'#', b"'", b'`', b'@', b'?'):
        start -= 1
    return start, end


def word_range(data, offset):
    if offset >= len(data) or data[offset] in SYMBOL_BREAK:
        return None
    start, end = offset, offset
    while start > 0 and data[start - 1] not in SYMBOL_BREAK:
        start -= 1
    while end + 1 < len(data) and data[end + 1] not in SYMBOL_BREAK:
        end += 1
    while start < end and data[start] in SYMBOL_PREFIX:
        start += 1
    return start, end


def byte_offset(data, line, column):
    start = 0
    for _ in range(line - 1):
        newline = data.find(b'\n', start)
        if newline < 0:
            break
        start = newline + 1
    return min(start + column - 1, max(len(data) - 1, 0))


def line_column(data, offset):
    return data.count(b'\n', 0, offset) + 1, offset - (data.rfind(b'\n', 0, offset) + 1) + 1


def buffer_namespace(data):
    match = NS_FORM.search(data)
    return match[1].decode() if match else None


def ns_form_code(data):
    match = NS_FORM.search(data)
    if not match:
        return ''
    span = form_range(data, match.start(0) + match[0].index(b'('), False)
    return data[span[0]:span[1] + 1].decode('utf-8', 'replace') if span else ''


def runtime_directory():
    base = os.environ.get('XDG_RUNTIME_DIR') or os.environ.get('TMPDIR') or '/tmp'
    directory = Path(base) / f'kak-nrepl-{os.getuid()}'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    return directory


def paths_for(root):
    digest = hashlib.sha1(str(root).encode()).hexdigest()[:12]
    name = re.sub(r'[^A-Za-z0-9._-]', '_', Path(root).name) or 'root'
    base = str(runtime_directory() / f'{name}-{digest}')
    return {key: base + suffix for key, suffix in [
        ('socket', '.sock'), ('log', '.log'), ('lock', '.lock'), ('stderr', '.stderr'),
        ('jack-in', '.jack-in'), ('jack-in-output', '.jack-in.log')]}


def socket_answers(path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(path)
        return True
    except OSError:
        return False
    finally:
        client.close()


def spawn_daemon(root, paths):
    with open(paths['lock'], 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if socket_answers(paths['socket']):
            return
        with open(paths['stderr'], 'a') as errors:
            subprocess.Popen([sys.executable, os.path.abspath(__file__), 'daemon', str(root)],
                             cwd=str(root), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=errors, start_new_session=True, close_fds=True)


def daemon_socket(root, autostart):
    paths = paths_for(root)
    deadline = time.monotonic() + DAEMON_START_TIMEOUT
    spawned = False
    while True:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            client.connect(paths['socket'])
            return client
        except OSError as error:
            client.close()
            if error.errno not in (errno.ENOENT, errno.ECONNREFUSED):
                raise
            if not autostart:
                raise ValueError(f'not connected to an nREPL for {root}; use , c c to connect')
            if not spawned:
                spawn_daemon(root, paths)
                spawned = True
            elif time.monotonic() > deadline:
                raise ValueError(f'the nREPL daemon for {root} did not start; see {paths["stderr"]}')
            time.sleep(0.05)


def daemon_request(root, request, autostart=True, timeout=REQUEST_TIMEOUT):
    client = daemon_socket(root, autostart)
    try:
        client.settimeout(timeout)
        client.sendall(json.dumps(request).encode() + b'\n')
        buffer = b''
        while b'\n' not in buffer:
            chunk = client.recv(65536)
            if not chunk:
                raise ValueError(f'the nREPL daemon for {root} hung up; see {paths_for(root)["stderr"]}')
            buffer += chunk
        return json.loads(buffer.split(b'\n', 1)[0])
    finally:
        client.close()


def push_command(session, client, command):
    if not session:
        return
    if client:
        command = 'evaluate-commands -try-client ' + quote(client) + ' ' + quote(command)
    try:
        subprocess.run(['kak', '-p', session], input=command, text=True, timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except (OSError, subprocess.SubprocessError):
        pass


def announce(message, face=None):
    """Kakoune command that echoes a message and records it as the last REPL report."""
    echo = ('echo -markup ' + quote('{' + face + '}' + markup_escape(message)) if face
            else 'echo -- ' + quote(message))
    return 'set-option global nrepl_report ' + quote(message) + '\n' + echo


def advertises(ops, *names):
    return any(op == name or op.endswith('/' + name) for op in ops for name in names)


def statuses(messages):
    return [state for message in messages for state in message.get('status') or []]


def failed(messages):
    return any(state in ('eval-error', 'error') for state in statuses(messages))


class Daemon:

    def __init__(self, root):
        self.root = Path(root)
        self.paths = paths_for(self.root)
        self.state = threading.RLock()
        self.connecting = threading.Lock()
        self.output = threading.Lock()
        self.pending = {}
        self.counter = 0
        self.connection = None
        self.session = None
        self.ops = []
        self.port = None
        self.error = 'not connected yet'
        self.running = True
        self.sessions = set()
        self.namespaces = {}
        self.log = open(self.paths['log'], 'a', buffering=1, errors='replace')

    def write_log(self, text):
        with self.output:
            self.log.write(text)

    def write_stream(self, prefix, text):
        self.write_log(''.join(f'{prefix}{line}\n' for line in text.split('\n')))

    def next_id(self):
        with self.state:
            self.counter += 1
            return f'kak-{self.counter}'

    def port_from_file(self):
        port_file = self.root / '.nrepl-port'
        if not port_file.is_file():
            return None, f'no .nrepl-port in {self.root}; jack in with , c j or start your REPL'
        text = port_file.read_text().strip()
        if not text.isdigit():
            return None, f'{port_file} holds {text!r}, not a port number'
        return int(text), None

    def broadcast(self, command):
        with self.state:
            sessions = list(self.sessions)
        for session in sessions:
            push_command(session, '', command)

    def ensure_connection(self):
        with self.connecting:
            with self.state:
                if self.connection:
                    return True
            port, failure = self.port_from_file()
            if failure:
                with self.state:
                    self.error = failure
                return False
            try:
                connection = socket.create_connection(('127.0.0.1', port), CONNECT_TIMEOUT)
            except OSError as error:
                with self.state:
                    self.error = f'nothing answers on port {port} ({error.strerror or error}); is the REPL still running?'
                return False
            connection.settimeout(None)
            with self.state:
                self.connection = connection
                self.port = port
                self.error = None
            threading.Thread(target=self.read_loop, args=(connection,), daemon=True).start()
            return self.handshake()

    def handshake(self):
        clone = self.request_sync({'op': 'clone'}, CONNECT_TIMEOUT * 4)['messages']
        session = next((m['new-session'] for m in clone if 'new-session' in m), None)
        if not session:
            self.disconnect(f'the nREPL on port {self.port} gave no session')
            return False
        with self.state:
            self.session = session
        describe = self.request_sync({'op': 'describe', 'session': session},
                                     CONNECT_TIMEOUT * 4)['messages']
        ops = {}
        for message in describe:
            ops.update(message.get('ops') or {})
        with self.state:
            self.ops = sorted(ops)
        self.write_log(f'{LOG_SEPARATOR}\n; connected to 127.0.0.1:{self.port} ({len(self.ops)} ops)\n')
        self.broadcast(f"set-option global nrepl_port {self.port}\nset-option global nrepl_connected true")
        return True

    def send(self, message):
        with self.state:
            connection = self.connection
        if not connection:
            raise ValueError('the nREPL connection is gone')
        connection.sendall(bencode(message))

    def register(self, message, reply=None):
        record = {'id': message['id'], 'messages': [], 'done': threading.Event(), 'reply': reply,
                  'values': [], 'forced': None, 'namespace': '', 'errors': [], 'out': [], 'ex': '',
                  'statuses': [], 'streams': {}, 'retried': False}
        with self.state:
            self.pending[record['id']] = record
        return record

    def request_sync(self, message, timeout):
        message = dict(message, id=self.next_id())
        record = self.register(message)
        try:
            self.send(message)
        except (OSError, ValueError):
            self.finish(record, 'disconnected')
        record['done'].wait(timeout)
        with self.state:
            self.pending.pop(record['id'], None)
        return record

    def read_loop(self, connection):
        buffer = b''
        try:
            while True:
                chunk = connection.recv(65536)
                if not chunk:
                    break
                messages, buffer = bdecode(buffer + chunk)
                for message in messages:
                    self.dispatch(message)
        except (OSError, ValueError):
            pass
        finally:
            self.disconnect(f'the nREPL on port {self.port} closed the connection')

    def dispatch(self, message):
        with self.state:
            record = self.pending.get(message.get('id'))
        if not record:
            return
        record['messages'].append(message)
        self.record_message(record, message)
        if 'done' in (message.get('status') or []):
            self.finish(record, None)

    def record_message(self, record, message):
        for stream, prefix in [('out', '; (out) '), ('err', '; (err) ')]:
            if stream in message:
                self.flush_streams(record, keep=stream)
                buffered = record['streams'].get(stream, '') + message[stream]
                complete, _, remainder = buffered.rpartition('\n')
                record['streams'][stream] = remainder
                if complete:
                    self.write_stream(prefix, complete)
                (record['errors'] if stream == 'err' else record['out']).append(message[stream])
        if 'ns' in message:
            record['namespace'] = message['ns']
        if 'value' in message:
            self.flush_streams(record)
            record['values'].append(message['value'])
            self.write_log(message['value'] + '\n')
        if 'ex' in message:
            record['ex'] = message['ex']
        record['statuses'].extend(message.get('status') or [])

    def flush_streams(self, record, keep=None):
        for stream, prefix in [('out', '; (out) '), ('err', '; (err) ')]:
            partial = record['streams'].get(stream)
            if partial and stream != keep:
                record['streams'][stream] = ''
                self.write_stream(prefix, partial)

    def outcome(self, record):
        if record['forced']:
            return record['forced']
        if 'eval-error' in record['statuses'] or 'error' in record['statuses']:
            return 'error'
        return 'interrupted' if 'interrupted' in record['statuses'] else 'ok'

    def finish(self, record, forced_status):
        with self.state:
            if record['done'].is_set():
                return
            self.pending.pop(record['id'], None)
        self.flush_streams(record)
        record['forced'] = forced_status
        status = self.outcome(record)
        reply = record['reply']
        if reply and self.should_retry(record, status):
            # Retrying waits on replies, so it must not run on the reader thread.
            threading.Thread(target=self.retry_in_namespace, args=(record,), daemon=True).start()
            return
        record['done'].set()
        if status == 'disconnected':
            self.write_stream('; (err) ', self.error or 'the nREPL connection was lost')
        elif status == 'interrupted':
            self.write_log('; interrupted\n')
        if reply:
            push_command(reply['session'], reply['client'], self.render(record, status, reply))

    def should_retry(self, record, status):
        """The buffer's namespace is not loaded yet: evaluate its ns form, then retry once."""
        missing = 'namespace-not-found' in record['statuses'] or any(
            re.search(r'No namespace: \S+ found', error) for error in record['errors'])
        return (status == 'error' and missing and not record['retried']
                and bool(record['reply'].get('ns-form')) and 'request' in record)

    def retry_in_namespace(self, record):
        reply = record['reply']
        self.write_log(f'; {reply["ns"]} is not loaded; evaluating its ns form first\n')
        loaded = self.request_sync({'op': 'eval', 'code': reply['ns-form'], 'ns': 'user',
                                    'session': self.session}, QUERY_TIMEOUT)
        if failed(loaded['messages']) or not loaded['done'].is_set():
            record['retried'] = True
            record['done'].clear()
            self.finish(record, None)
            return
        retry = dict(record['request'], id=self.next_id())
        again = self.register(retry, reply)
        again['request'] = retry
        again['retried'] = True
        record['done'].set()
        try:
            self.send(retry)
        except (OSError, ValueError):
            self.finish(again, 'disconnected')

    def render(self, record, status, reply):
        """Kakoune commands showing an evaluation result: echo, inline text and a popup."""
        values = '\n'.join(record['values'])
        error = ''.join(record['errors']).strip() or record['ex']
        mode = reply.get('mode', 'eval')
        commands = []
        if mode == 'test':
            return self.render_test(record, status, values, error)
        if status == 'ok':
            shown = values.strip() or 'nil'
            flat = one_line(shown)
            prefix = (record['namespace'] or 'nrepl') + '=> '
            commands.append(announce(prefix + flat))
            inline, face = '; => ' + flat, 'InlayEvalResult'
            if '\n' in shown or len(prefix + flat) > 120:
                commands.append(self.popup(reply, record['namespace'] + '=>', shown))
        elif status == 'interrupted':
            commands.append(announce('nrepl: interrupted'))
            inline, face = '; interrupted', 'InlayEvalError'
        else:
            if error:
                message = error
            elif 'namespace-not-found' in record['statuses']:
                message = f'namespace {reply.get("ns") or "?"} is not loaded; evaluate its ns form (, e b)'
            elif status == 'disconnected':
                message = self.error or 'the nREPL connection was lost'
            else:
                message = 'the server reported ' + (', '.join(sorted(set(record['statuses']) - {'done'})) or status)
            commands.append(announce('nrepl ' + status + ': ' + one_line(message), 'Error'))
            inline, face = '; !! ' + one_line(message), 'InlayEvalError'
            commands.append(self.popup(reply, 'nrepl ' + status, message))
        if reply.get('buffer') and reply.get('line'):
            text = inline if len(inline) <= INLINE_WIDTH else inline[:INLINE_WIDTH - 1] + '…'
            commands.append('nrepl-inline ' + ' '.join(map(quote, [
                reply['buffer'], reply['line'], reply['timestamp'],
                '{' + face + '}  ' + markup_escape(text)])))
        return '\n'.join(commands)

    def render_test(self, record, status, values, error):
        counters = {key: int(value) for key, value in
                    re.findall(r':(test|pass|fail|error)\s+(\d+)', values)}
        output = ''.join(record['out']).strip()
        if status != 'ok' or not counters:
            detail = error or output or values or status
            return (announce('nrepl: tests did not run: ' + one_line(detail), 'Error') + '\n' +
                    'info -title ' + quote('nrepl tests') + ' -- ' + quote(self.clip(detail)))
        summary = (f'nrepl: {counters.get("test", 0)} tests, {counters.get("pass", 0)} assertions '
                   f'passed, {counters.get("fail", 0)} failed, {counters.get("error", 0)} errored')
        if counters.get('fail') or counters.get('error'):
            return (announce(summary, 'Error') + '\n' + 'info -title ' + quote('nrepl tests') +
                    ' -- ' + quote(self.clip(output or summary)))
        return announce(summary)

    def clip(self, text):
        lines = str(text).split('\n')
        if len(lines) > INFO_LINES:
            lines = lines[:INFO_LINES] + [f'… {len(lines) - INFO_LINES} more lines (, l l)']
        return '\n'.join(lines)

    def popup(self, reply, title, text):
        anchor = f'-anchor {reply["line"]}.1 ' if reply.get('line') and reply.get('buffer') else ''
        return 'info -style above ' + anchor + '-title ' + quote(title) + ' -- ' + quote(self.clip(text))

    def disconnect(self, reason):
        with self.state:
            was_connected = self.connection is not None
            if self.connection:
                try:
                    self.connection.close()
                except OSError:
                    pass
                self.write_log(f'; {reason}\n')
            self.connection = None
            self.session = None
            self.namespaces = {}
            self.ops = []
            self.error = reason
            records = list(self.pending.values())
        for record in records:
            self.finish(record, 'disconnected')
        if was_connected:
            self.broadcast('set-option global nrepl_connected false\n' + announce('nrepl: ' + reason))

    def status(self):
        with self.state:
            return {'root': str(self.root), 'connected': bool(self.connection), 'port': self.port,
                    'session': self.session, 'ops': list(self.ops), 'error': self.error,
                    'pending': sorted(self.pending), 'log': self.paths['log']}

    def ensure_namespace(self, namespace, ns_form):
        """Evaluate the buffer's ns form before code in its namespace whenever that form has
        changed since it last loaded (first use, fixed, or new requires). Returns the error
        text when the ns form fails. A failed ns form still creates the namespace, so
        whether the namespace exists says nothing about its requires."""
        if not namespace or namespace == 'user' or not ns_form:
            return None
        if self.namespaces.get(namespace) == ns_form:
            return None
        self.write_log(f'; loading the ns form of {namespace}\n')
        loaded = self.request_sync({'op': 'eval', 'ns': 'user', 'session': self.session,
                                    'code': ns_form}, QUERY_TIMEOUT)
        if failed(loaded['messages']) or not loaded['done'].is_set():
            self.namespaces.pop(namespace, None)
            error = ''.join(loaded['errors']).strip() or loaded['ex'] or 'it did not compile'
            return f'the ns form of {namespace} failed to load: {error}'
        self.namespaces[namespace] = ns_form
        return None

    def start_evaluation(self, request):
        problem = None
        if request.get('ns') and not re.match(r'\s*\(ns\s', request['code']):
            problem = self.ensure_namespace(request['ns'], request.get('ns-form', ''))
        message = {'op': 'eval', 'code': request['code'], 'id': self.next_id()}
        for key in ['ns', 'file']:
            if request.get(key):
                message[key] = request[key]
        for key in ['line', 'column']:
            if str(request.get(key, '')).isdigit():
                message[key] = int(request[key])
        with self.state:
            message['session'] = self.session
        reply = {'session': request.get('kak-session', ''), 'client': request.get('kak-client', ''),
                 'buffer': request.get('buffer', ''), 'line': str(request.get('result-line') or ''),
                 'timestamp': str(request.get('timestamp', '')), 'ns': request.get('ns', ''),
                 'ns-form': request.get('ns-form', ''), 'mode': request.get('mode', 'eval')}
        record = self.register(message, reply)
        record['request'] = message
        if problem:
            # Evaluating in a namespace that failed to load only yields namespace-not-found;
            # report why it failed instead.
            record['errors'].append(problem)
            record['statuses'].append('error')
            record['retried'] = True
            self.finish(record, None)
            return {'id': record['id']}
        where = f' {request["file"]}:{request.get("line", "")}' if request.get('file') else ''
        self.write_log(f'{LOG_SEPARATOR}\n; {request.get("ns") or "user"}{where}\n{request["code"]}\n')
        self.send(message)
        return {'id': record['id']}

    def handle(self, request):
        kind = request.get('kind')
        if request.get('kak-session'):
            with self.state:
                self.sessions.add(request['kak-session'])
        if kind == 'status':
            self.ensure_connection()
            return self.status()
        if kind == 'shutdown':
            self.running = False
            return {'stopped': True}
        if kind == 'log':
            self.write_log(request.get('text', ''))
            return {'logged': True}
        if not self.ensure_connection():
            return {'error': self.error}
        if kind == 'eval':
            return self.start_evaluation(request)
        if kind == 'op':
            message = dict(request['message'])
            message.setdefault('session', self.session)
            if message.get('op') == 'eval' and request.get('ns-form'):
                self.ensure_namespace(message.get('ns'), request['ns-form'])
            timeout = request.get('timeout', REQUEST_TIMEOUT)
            if message.get('op') == 'eval':
                self.write_log(f'{LOG_SEPARATOR}\n; {message.get("ns") or "user"}\n{message.get("code", "")}\n')
            record = self.request_sync(message, timeout)
            if record['forced'] == 'disconnected':
                return {'error': self.error or 'the nREPL connection was lost'}
            if not record['done'].is_set():
                return {'error': f'no answer within {timeout:g}s; interrupt with , e i'}
            return {'messages': record['messages']}
        if kind == 'interrupt':
            # Babashka interrupts without advertising the op, so always ask.
            with self.state:
                targets = sorted(record_id for record_id, record in self.pending.items()
                                 if record['reply'])
            for target in targets:
                message = {'op': 'interrupt', 'session': self.session, 'interrupt-id': target,
                           'id': self.next_id()}
                self.register(message)
                self.send(message)
            return {'interrupted': targets}
        raise ValueError(f'unknown daemon request {kind!r}')

    def serve_client(self, connection):
        try:
            connection.settimeout(REQUEST_TIMEOUT)
            buffer = b''
            while b'\n' not in buffer:
                chunk = connection.recv(65536)
                if not chunk:
                    return
                buffer += chunk
            try:
                reply = self.handle(json.loads(buffer.split(b'\n', 1)[0]))
            except (OSError, ValueError) as error:
                reply = {'error': str(error)}
            connection.sendall(json.dumps(reply).encode() + b'\n')
        except OSError:
            pass
        finally:
            connection.close()
            if not self.running:
                # Wake the accept loop so it notices the shutdown.
                socket_answers(self.paths['socket'])

    def serve(self):
        with open(self.paths['lock'], 'a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if socket_answers(self.paths['socket']):
                return 0
            Path(self.paths['socket']).unlink(missing_ok=True)
            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            listener.bind(self.paths['socket'])
            os.chmod(self.paths['socket'], 0o600)
            listener.listen(16)
        try:
            while self.running:
                connection, _ = listener.accept()
                threading.Thread(target=self.serve_client, args=(connection,), daemon=True).start()
        finally:
            listener.close()
            Path(self.paths['socket']).unlink(missing_ok=True)
            self.disconnect('the Kakoune nREPL client stopped')
        return 0


# Each entry point runs inside `evaluate-commands -draft %{ execute-keys % ... }`, so
# kak_selection holds the whole buffer, and prints Kakoune commands for the caller to run.

class Context:

    def __init__(self):
        env = os.environ
        self.session = env.get('kak_session', '')
        self.client = env.get('kak_client', '')
        self.buffile = env.get('kak_buffile', '')
        self.bufname = env.get('kak_bufname', '')
        self.timestamp = env.get('kak_timestamp', '')
        self.text = env.get('kak_selection', '').encode()
        line, _, column = env.get('kak_opt_nrepl_cursor', '1 1').partition(' ')
        self.line, self.column = int(line or 1), int(column or 1)
        self.override = env.get('kak_opt_nrepl_namespace', '')
        self.root = project_root(self.buffile or os.path.join(os.getcwd(), 'scratch.clj'))

    @property
    def namespace(self):
        return self.override or buffer_namespace(self.text) or 'user'

    def offset(self):
        return byte_offset(self.text, self.line, self.column)

    def span(self, kind):
        if kind == 'word':
            return word_range(self.text, self.offset())
        return form_range(self.text, self.offset(), kind == 'root')

    def snippet(self, span):
        return self.text[span[0]:span[1] + 1].decode('utf-8', 'replace')

    def request(self, **extra):
        return dict({'kak-session': self.session, 'kak-client': self.client}, **extra)


def fail(message):
    return 'fail ' + quote('nrepl: ' + message)


def eval_request(ctx, code, line, column, end_line, namespace, mode='eval'):
    return ctx.request(kind='eval', code=code, ns=namespace, file=ctx.buffile or None,
                       line=line, column=column, buffer=ctx.bufname, **{
                           'result-line': end_line, 'timestamp': ctx.timestamp,
                           'ns-form': ns_form_code(ctx.text), 'mode': mode})


def send(ctx, requests, label):
    for request in requests:
        reply = daemon_request(ctx.root, request, timeout=DAEMON_START_TIMEOUT * 4)
        if reply.get('error'):
            return 'set-option global nrepl_connected false\n' + fail(reply['error'])
    return ('nrepl-arm-results\nset-option global nrepl_connected true\n' +
            announce('nrepl: evaluating ' + label + '…'))


def command_eval(ctx, kind):
    if kind in ('form', 'root', 'word'):
        span = ctx.span(kind)
        if not span:
            return fail(f'no {kind} at the cursor')
        code = ctx.snippet(span)
        (line, column), (end_line, _) = line_column(ctx.text, span[0]), line_column(ctx.text, span[1])
        namespace = 'user' if kind != 'word' and re.match(r'\s*\(ns\s', code) else ctx.namespace
        return send(ctx, [eval_request(ctx, code, line, column, end_line, namespace)], kind)
    if kind == 'buffer':
        code = ctx.text.decode('utf-8', 'replace')
        return send(ctx, [eval_request(ctx, code, 1, 1, None, 'user')], 'buffer')
    if kind == 'file':
        if not ctx.buffile:
            return fail('this buffer has no file; write it first')
        code = '(clojure.core/load-file ' + json.dumps(ctx.buffile) + ')'
        return send(ctx, [eval_request(ctx, code, 1, 1, None, 'user')], 'file')
    if kind == 'selection':
        texts = shlex.split(os.environ.get('kak_quoted_opt_nrepl_saved_text', ''))
        descs = os.environ.get('kak_opt_nrepl_saved_descs', '').split()
        requests = []
        for code, desc in zip(texts, descs):
            if not code.strip():
                continue
            points = sorted(tuple(map(int, point.split('.'))) for point in desc.split(','))
            namespace = 'user' if re.match(r'\s*\(ns\s', code) else ctx.namespace
            requests.append(eval_request(ctx, code, points[0][0], points[0][1], points[1][0], namespace))
        if not requests:
            return fail('the selection is empty')
        return send(ctx, requests, 'selection')
    raise ValueError(f'unknown eval kind {kind!r}')


def eval_sync(ctx, code, namespace):
    reply = daemon_request(ctx.root, ctx.request(kind='op', timeout=SYNC_TIMEOUT, message={
        'op': 'eval', 'code': code, 'ns': namespace}, **{'ns-form': ns_form_code(ctx.text)}),
        timeout=SYNC_TIMEOUT + REPLY_MARGIN)
    if reply.get('error'):
        return None, reply['error']
    messages = reply['messages']
    if failed(messages):
        error = ''.join(m.get('err', '') for m in messages).strip() or \
            ''.join(m.get('ex', '') for m in messages).strip()
        if not error and 'namespace-not-found' in statuses(messages):
            error = f'namespace {namespace} is not loaded; evaluate its ns form (, e b)'
        if 'namespace-not-found' in statuses(messages) and ns_form_code(ctx.text):
            loaded = daemon_request(ctx.root, ctx.request(kind='op', timeout=SYNC_TIMEOUT, message={
                'op': 'eval', 'code': ns_form_code(ctx.text), 'ns': 'user'}))
            if not loaded.get('error') and not failed(loaded['messages']):
                return eval_sync(ctx, code, namespace)
        return None, error or 'evaluation failed'
    return '\n'.join(m['value'] for m in messages if 'value' in m), None


def command_replace(ctx):
    span = ctx.span('form')
    if not span:
        return fail('no form at the cursor')
    value, error = eval_sync(ctx, ctx.snippet(span), ctx.namespace)
    if error:
        return fail(one_line(error))
    (line, column), (end_line, end_column) = line_column(ctx.text, span[0]), line_column(ctx.text, span[1])
    return (f'select {line}.{column},{end_line}.{end_column}\n'
            f'set-register c {quote(value)}\nexecute-keys %{{"cR}}\n' + announce('nrepl: replaced with ' + one_line(value)))


def command_comment(ctx, kind):
    span = ctx.span(kind)
    if not span:
        return fail(f'no {kind} at the cursor')
    value, error = eval_sync(ctx, ctx.snippet(span), ctx.namespace)
    if error:
        return fail(one_line(error))
    (_, column), (end_line, _) = line_column(ctx.text, span[0]), line_column(ctx.text, span[1])
    indent = ' ' * (column - 1)
    comment = '\n'.join(indent + (';; => ' if index == 0 else ';;    ') + part
                        for index, part in enumerate(value.split('\n')))
    edit = f'select {end_line}.1,{end_line}.1\nset-register c {quote(comment)}\nexecute-keys %{{o<esc>"cP}}'
    return 'evaluate-commands -draft ' + quote(edit) + '\n' + announce('nrepl: => ' + one_line(value))


def server_status(ctx):
    return daemon_request(ctx.root, ctx.request(kind='status'), timeout=DAEMON_START_TIMEOUT * 4)


def op(ctx, message, timeout, autostart=True):
    reply = daemon_request(ctx.root, ctx.request(kind='op', timeout=timeout, message=message),
                           autostart=autostart, timeout=timeout + REPLY_MARGIN)
    if reply.get('error'):
        raise ValueError(reply['error'])
    return reply['messages']


def command_status(ctx):
    status = server_status(ctx)
    if not status.get('connected'):
        return 'set-option global nrepl_connected false\n' + fail('not connected: ' + str(status.get('error')))
    ops = status.get('ops') or []
    detail = '\n'.join([f'connected to 127.0.0.1:{status["port"]}', f'root: {status["root"]}',
                        f'namespace: {ctx.namespace}', f'log: {status["log"]}',
                        'cider-nrepl: ' + ('yes' if advertises(ops, 'test-var-query') else 'no (tests and refresh use plain eval)'),
                        f'pending: {", ".join(status.get("pending") or []) or "none"}'])
    return (f'set-option global nrepl_port {status["port"]}\n'
            'set-option global nrepl_connected true\n'
            'info -title nREPL -- ' + quote(detail) + '\n' + announce(f'nrepl: connected to port {status["port"]}'))


def port_alive(root):
    port_file = Path(root) / '.nrepl-port'
    try:
        port = int(port_file.read_text().strip())
        socket.create_connection(('127.0.0.1', port), 1).close()
        return port
    except (OSError, ValueError):
        return None


def bb_tasks(root):
    try:
        output = subprocess.run(['bb', 'tasks'], cwd=root, capture_output=True, text=True,
                                timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    tasks = {}
    for line in output.splitlines()[1:]:
        name, _, doc = line.strip().partition(' ')
        if name:
            tasks[name] = doc.strip()
    return tasks


def jack_in_command(root):
    override = shlex.split(os.environ.get('kak_quoted_opt_nrepl_jack_in_command', ''))
    if override:
        return override
    root = Path(root)
    if (root / 'bb.edn').exists() and shutil.which('bb'):
        tasks = bb_tasks(root)
        for name in ['nrepl', 'dev', 'repl']:
            if name in tasks and (name == 'nrepl' or re.search(r'n?repl', tasks[name], re.I)):
                return ['bb', name]
    if (root / 'deps.edn').exists():
        deps = ('{:deps {nrepl/nrepl {:mvn/version "' + NREPL_VERSION + '"} '
                'cider/cider-nrepl {:mvn/version "' + CIDER_NREPL_VERSION + '"}}}')
        dev = re.search(r':dev\s*\{', (root / 'deps.edn').read_text(errors='replace'))
        return ['clojure', '-Sdeps', deps, '-M' + (':dev' if dev else ''), '-m', 'nrepl.cmdline',
                '--middleware', '[cider.nrepl/cider-middleware]']
    if (root / 'project.clj').exists():
        return ['lein', 'update-in', ':plugins', 'conj',
                f'[cider/cider-nrepl "{CIDER_NREPL_VERSION}"]', '--', 'repl', ':headless']
    if (root / 'bb.edn').exists():
        return [sys.executable, os.path.abspath(__file__), 'bb-server']
    return None


def command_jack_in(ctx):
    port = port_alive(ctx.root)
    if port:
        return command_status(ctx)
    command = jack_in_command(ctx.root)
    if not command:
        return fail(f'no deps.edn, bb.edn or project.clj in {ctx.root}; set nrepl_jack_in_command')
    if not shutil.which(command[0]):
        return fail(f'{command[0]} is not on PATH; start kak from the project shell (direnv)')
    stale = ctx.root / '.nrepl-port'
    if stale.exists():
        stale.unlink()
    paths = paths_for(ctx.root)
    shown = shlex.join(command)
    if os.environ.get('TMUX') and shutil.which('tmux'):
        script = shown + '; status=$?; printf "\\n[nrepl exited with %s; press enter]" "$status"; read _'
        window = subprocess.run(['tmux', 'new-window', '-d', '-P', '-F', '#{window_id}',
                                 '-n', 'nrepl', '-c', str(ctx.root), 'sh', '-c', script],
                                capture_output=True, text=True).stdout.strip()
        Path(paths['jack-in']).write_text('tmux ' + window + '\n')
        where = 'tmux window "nrepl"'
    else:
        with open(paths['jack-in-output'], 'w') as output:
            process = subprocess.Popen(command, cwd=ctx.root, stdin=subprocess.DEVNULL, stdout=output,
                                       stderr=subprocess.STDOUT, start_new_session=True)
        Path(paths['jack-in']).write_text(f'pid {process.pid}\n')
        where = paths['jack-in-output']
    subprocess.Popen([sys.executable, os.path.abspath(__file__), 'await-port', str(ctx.root),
                      ctx.session, ctx.client], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return announce(f'nrepl: jacking in with `{shown}` ({where}); connecting when it is up…')


def await_port(root, session, client):
    deadline = time.monotonic() + JACK_IN_TIMEOUT
    while time.monotonic() < deadline:
        if port_alive(root):
            status = daemon_request(Path(root), {'kind': 'status', 'kak-session': session},
                                    timeout=DAEMON_START_TIMEOUT * 4)
            if status.get('connected'):
                push_command(session, client, f'set-option global nrepl_port {status["port"]}\n'
                             'set-option global nrepl_connected true\n' +
                             announce(f'nrepl: connected to port {status["port"]}'))
                return 0
        time.sleep(0.5)
    push_command(session, client, announce('nrepl: no .nrepl-port after '
                                           f'{JACK_IN_TIMEOUT:g}s; check the nrepl window', 'Error'))
    return 1


def command_disconnect(ctx, stop_server):
    paths = paths_for(ctx.root)
    try:
        daemon_request(ctx.root, {'kind': 'shutdown'}, autostart=False, timeout=DAEMON_START_TIMEOUT)
    except (OSError, ValueError):
        pass
    message = 'nrepl: disconnected'
    if stop_server:
        record = Path(paths['jack-in'])
        kind, _, target = (record.read_text().strip() if record.exists() else '').partition(' ')
        if kind == 'tmux':
            subprocess.run(['tmux', 'kill-window', '-t', target], capture_output=True)
        elif kind == 'pid':
            try:
                os.killpg(int(target), signal.SIGTERM)
            except (OSError, ValueError):
                pass
        record.unlink(missing_ok=True)
        message = 'nrepl: disconnected and stopped the jacked-in REPL' if kind else \
            'nrepl: disconnected (no jacked-in REPL to stop)'
    return 'set-option global nrepl_connected false\n' + announce(message)


def command_interrupt(ctx):
    reply = daemon_request(ctx.root, ctx.request(kind='interrupt'), autostart=False)
    if reply.get('error'):
        return fail(reply['error'])
    targets = reply.get('interrupted') or []
    return announce('nrepl: ' + ('interrupting ' + ', '.join(targets) if targets else 'nothing is running'))


# Tests: cider-nrepl's test ops when the server has them (failures go to the *make* buffer so
# you can jump to them), plain clojure.test through eval otherwise (Babashka).

def counters_code(body):
    return ("(binding [clojure.test/*report-counters* (ref clojure.test/*initial-report-counters*)] "
            + body + " @clojure.test/*report-counters*)")


def test_target(ctx, scope):
    namespace = ctx.namespace
    if scope == 'cursor':
        span = ctx.span('root')
        match = TEST_DEFINER.match(ctx.snippet(span)) if span else None
        if not match:
            return None, 'the cursor is not inside a deftest'
        return (namespace, match[1]), None
    return (namespace, None), None


def command_test(ctx, scope):
    status = server_status(ctx)
    if not status.get('connected'):
        return fail('not connected: ' + str(status.get('error')))
    target, error = (None, None) if scope in ('all', 'rerun') else test_target(ctx, scope)
    if error:
        return fail(error)
    cider = advertises(status.get('ops') or [], 'test-var-query')
    if cider:
        arguments = [scope]
        if target:
            namespace, var = target
            namespaces = [namespace] if namespace.endswith('-test') or var else [namespace, namespace + '-test']
            arguments += [namespace + '/' + var] if var else namespaces
        command = [sys.executable, os.path.abspath(__file__), 'test-report', str(ctx.root),
                   ctx.session, ctx.client, *arguments]
        return 'set-option local makecmd ' + quote(shlex.join(command)) + '\nmake'
    if scope == 'rerun':
        return fail('rerunning failures needs cider-nrepl; this server lacks it')
    if scope == 'cursor':
        namespace, var = target
        body = (f"(do (require '{namespace} :reload) "
                + counters_code(f"(clojure.test/test-vars [(resolve '{namespace}/{var})])") + ")")
    else:
        if scope == 'namespace':
            namespace = target[0]
            names = [namespace] if namespace.endswith('-test') else [namespace, namespace + '-test']
        else:
            names = test_namespaces(ctx.root)
            if not names:
                return fail(f'no test namespaces under {ctx.root}/test')
        quoted = "'[" + ' '.join(names) + "]"
        body = ("(do (doseq [n " + quoted + "] (try (require n :reload) (catch Exception e "
                "(when-not (re-find #\"(?i)could not (locate|find)\" (str e)) (throw e))))) "
                "(apply clojure.test/run-tests (filter find-ns " + quoted + ")))")
    body = '(binding [clojure.test/*test-out* *out*] ' + body + ')'
    request = eval_request(ctx, body, None, None, None, 'user', mode='test')
    request.update(buffer='', **{'result-line': ''})
    return send(ctx, [request], 'tests')


def test_namespaces(root):
    names = []
    for path in sorted(Path(root, 'test').rglob('*.clj*')):
        match = NS_FORM.search(path.read_bytes())
        if match:
            names.append(match[1].decode())
    return names


def test_message(verb, targets):
    if verb == 'rerun':
        return {'op': 'retest'}
    if verb == 'all':
        return {'op': 'test-var-query',
                'var-query': {'ns-query': {'project?': 'true', 'load-project-ns?': 'true'}}}
    if verb == 'namespace':
        return {'op': 'test-var-query', 'var-query': {'ns-query': {'exactly': list(targets)}}}
    return {'op': 'test-var-query',
            'var-query': {'ns-query': {'exactly': [targets[0].partition('/')[0]]},
                          'exactly': list(targets)}}


def test_text(value):
    if isinstance(value, (list, tuple)):
        value = ' '.join(map(str, value))
    return ' '.join(str('' if value is None else value).split())


def local_file_path(url):
    if url.startswith('file:'):
        url = urllib.request.url2pathname(urllib.parse.urlparse(url).path)
    return url if os.path.isabs(url) else ''


def test_report(root, session, client, verb, targets):
    """Runs in Kakoune's *make* buffer: one grep-style line per failure."""
    root = Path(root)

    def query(message, timeout):
        reply = daemon_request(root, {'kind': 'op', 'timeout': timeout, 'message': message},
                               timeout=timeout + REPLY_MARGIN)
        if reply.get('error'):
            raise ValueError(reply['error'])
        return reply['messages']

    print('$ nrepl test ' + (' '.join(targets) or verb), flush=True)
    if verb in ('cursor', 'namespace'):
        wanted = sorted({target.partition('/')[0] for target in targets})
        loaded = [n for n in wanted if not failed(query(
            {'op': 'eval', 'ns': 'user', 'code': f"(require '{n} :reload)"}, QUERY_TIMEOUT))]
        if not loaded:
            push_command(session, client, announce('nrepl: could not load ' + ', '.join(wanted), 'Error'))
            return 1
        if verb == 'namespace':
            targets = loaded
    verb = 'var' if verb == 'cursor' else verb
    messages = query(test_message(verb, targets), TEST_TIMEOUT)
    results, summary = {}, {}
    for message in messages:
        results.update(message.get('results') or {})
        summary.update(message.get('summary') or {})
    failures = 0
    for namespace in sorted(results):
        for var in sorted(results[namespace]):
            for entry in results[namespace][var]:
                if entry.get('type') not in ('fail', 'error'):
                    continue
                failures += 1
                info = {}
                for message in query({'op': 'info', 'ns': namespace, 'sym': var}, QUERY_TIMEOUT):
                    info.update(message)
                path = local_file_path(str(info.get('file') or ''))
                line = entry.get('line') or info.get('line') or 1
                detail = '; '.join(part for part in [
                    test_text(entry.get('context')), test_text(entry.get('message')),
                    test_text(entry.get('error')) if entry.get('type') == 'error' else
                    f'expected {test_text(entry.get("expected"))}, actual {test_text(entry.get("actual"))}']
                    if part)
                label = 'ERROR' if entry.get('type') == 'error' else 'FAIL'
                location = f'{path}:{line}:1: error: ' if path else '; '
                print(f'{location}{label} {namespace}/{var}: {detail}', flush=True)
    count = lambda key: int(summary.get(key) or 0)
    text = (f'nrepl: {count("test")} tests, {count("pass")} assertions passed, '
            f'{count("fail")} failed, {count("error")} errored')
    print('\n' + text, flush=True)
    push_command(session, client, announce(text, 'Error' if failures else None))
    return 1 if failures else 0


def command_refresh(ctx, verb):
    status = server_status(ctx)
    if not status.get('connected'):
        return fail('not connected: ' + str(status.get('error')))
    op_name = {'changed': 'refresh', 'all': 'refresh-all', 'clear': 'refresh-clear'}[verb]
    if advertises(status.get('ops') or [], op_name):
        subprocess.Popen([sys.executable, os.path.abspath(__file__), 'refresh-report',
                          str(ctx.root), ctx.session, ctx.client, op_name],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return announce(f'nrepl: {op_name}…')
    code = {'changed': "((requiring-resolve 'clojure.tools.namespace.repl/refresh))",
            'all': "((requiring-resolve 'clojure.tools.namespace.repl/refresh-all))",
            'clear': "((requiring-resolve 'clojure.tools.namespace.repl/clear))"}[verb]
    request = eval_request(ctx, code, None, None, None, 'user')
    request.update(buffer='', **{'result-line': ''})
    return send(ctx, [request], 'refresh (tools.namespace)')


def refresh_report(root, session, client, op_name):
    root = Path(root)
    reply = daemon_request(root, {'kind': 'op', 'timeout': REQUEST_TIMEOUT, 'message': {'op': op_name}})
    if reply.get('error'):
        push_command(session, client, announce('nrepl: ' + reply['error'], 'Error'))
        return 1
    reloaded, errors = [], []
    for message in reply['messages']:
        reloaded.extend(message.get('reloading') or [])
        if message.get('error'):
            errors.append(test_text(message['error']))
        if message.get('err'):
            errors.append(test_text(message['err']))
    if errors or failed(reply['messages']):
        detail = '\n'.join(errors) or 'refresh failed'
        daemon_request(root, {'kind': 'log', 'text': f'{LOG_SEPARATOR}\n; refresh failed\n{detail}\n'},
                       autostart=False)
        push_command(session, client, announce('nrepl: refresh failed: ' + one_line(detail), 'Error'))
        return 1
    push_command(session, client, announce(
        f'nrepl: reloaded {len(reloaded)} namespaces' + (': ' + ', '.join(reloaded) if reloaded else '')))
    return 0


def symbol_info(ctx):
    span = ctx.span('word')
    if not span:
        return None, None, 'no symbol at the cursor'
    symbol = ctx.snippet(span)
    status = server_status(ctx)
    if not status.get('connected'):
        return symbol, None, 'not connected: ' + str(status.get('error'))
    if advertises(status.get('ops') or [], 'info'):
        info = {}
        for message in op(ctx, {'op': 'info', 'ns': ctx.namespace, 'sym': symbol}, QUERY_TIMEOUT):
            info.update(message)
        return symbol, info if info.get('name') else None, None
    code = ("(when-let [v (resolve '" + symbol + ")] (let [m (meta v)] "
            "{:ns (str (:ns m)) :name (str (:name m)) :doc (:doc m) :file (:file m) :line (:line m) "
            ":arglists-str (pr-str (:arglists m)) "
            ":resource (some-> (:file m) clojure.java.io/resource str)}))")
    value, error = eval_sync(ctx, code, ctx.namespace)
    if error or not value or value == 'nil':
        return symbol, None, error
    info = {key: val for key, val in re.findall(r':([\w-]+) (?:"((?:[^"\\]|\\.)*)")', value)}
    line = re.search(r':line (\d+)', value)
    if line:
        info['line'] = int(line[1])
    info['file'] = info.pop('resource', '') or info.get('file', '')
    return symbol, info, None


def command_doc(ctx):
    symbol, info, error = symbol_info(ctx)
    if error:
        return fail(error)
    if not info:
        return fail(f'the REPL does not know {symbol} in {ctx.namespace}; evaluate the buffer first')
    name = '/'.join(part for part in [info.get('ns'), info.get('name')] if part)
    arglists = str(info.get('arglists-str') or '').strip()
    doc = str(info.get('doc') or 'no docstring').strip()
    text = '\n'.join(filter(None, [name, arglists, '', doc]))
    return (f'info -anchor {ctx.line}.{ctx.column} -style above -title ' + quote('doc') + ' -- ' + quote(text) + '\n' +
            announce(one_line(name + ' ' + arglists)))


def command_definition(ctx):
    symbol, info, error = symbol_info(ctx)
    if error:
        return fail(error)
    if not info:
        return fail(f'the REPL does not know {symbol}; evaluate the buffer first')
    url = str(info.get('file') or '')
    path = local_file_path(url)
    if not path or not os.path.isfile(path):
        where = 'the REPL' if not url or url == 'NO_SOURCE_PATH' else url
        return fail(f'{symbol} is defined in {where}, not a file on disk')
    line = int(info.get('line') or 1)
    # Code evaluated at the REPL can carry a line relative to the snippet (Babashka); trust
    # the file when the reported line does not mention the name.
    name = re.escape(str(info.get('name') or symbol.split('/')[-1]))
    lines = Path(path).read_text(errors='replace').split('\n')
    if not (0 < line <= len(lines) and re.search(name, lines[line - 1])):
        definer = re.compile(r'^\s*\(\S*def\S*\s+(?:\^\S+\s+)*' + name + r'(?:\s|$)')
        line = next((number for number, text in enumerate(lines, 1) if definer.match(text)), line)
    return f'edit -existing {quote(path)} {line} 1'


def completion_escape(text):
    return str(text).replace('\\', '\\\\').replace('|', '\\|')


def complete(buffile, session, bufname, namespace, line, column, timestamp, text, limit):
    root = project_root(buffile)
    typed = text.encode()[:max(int(column) - 1, 0)]
    start = len(typed)
    while start > 0 and typed[start - 1] not in SYMBOL_BREAK:
        start -= 1
    while start < len(typed) and typed[start] in SYMBOL_PREFIX:
        start += 1
    prefix = typed[start:].decode('utf-8', 'replace')
    if not prefix:
        return 0
    try:
        reply = daemon_request(root, {'kind': 'op', 'timeout': COMPLETE_TIMEOUT, 'message': {
            'op': 'complete', 'ns': namespace or 'user', 'prefix': prefix}},
            autostart=False, timeout=COMPLETE_TIMEOUT + 1)
    except (OSError, ValueError):
        return 0
    if reply.get('error') or 'unknown-op' in statuses(reply.get('messages') or []):
        return 0
    option = [f'{line}.{start + 1}@{timestamp}']
    for message in reply['messages']:
        for candidate in (message.get('completions') or [])[:int(limit)]:
            menu = ' '.join(str(part) for part in [candidate.get('ns'), candidate.get('type')] if part)
            option.append('|'.join([completion_escape(candidate.get('candidate', '')), 'completion-selected',
                                    completion_escape(markup_escape(menu))]))
    push_command(session, '', 'evaluate-commands -buffer ' + quote(bufname) + ' ' +
                 quote('set-option buffer nrepl_completions ' + ' '.join(map(quote, option))))
    return 0


def bb_server():
    """Babashka's nREPL does not write .nrepl-port; this wrapper does, and removes it on exit."""
    port_file = Path('.nrepl-port')
    process = subprocess.Popen(['bb', 'nrepl-server', '127.0.0.1:0'],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    port = None
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, lambda *_: process.terminate())
    try:
        for line in process.stdout:
            print(line, end='', flush=True)
            match = re.search(r'127\.0\.0\.1:(\d+)', line)
            if match and not port:
                port = match[1] + '\n'
                port_file.write_text(port)
        return process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait()
        if port and port_file.exists() and port_file.read_text() == port:
            port_file.unlink()


COMMANDS = {
    'eval': lambda ctx, kind: command_eval(ctx, kind),
    'replace': lambda ctx: command_replace(ctx),
    'comment': lambda ctx, kind: command_comment(ctx, kind),
    'status': lambda ctx: command_status(ctx),
    'connect': lambda ctx: command_status(ctx),
    'jack-in': lambda ctx: command_jack_in(ctx),
    'disconnect': lambda ctx: command_disconnect(ctx, False),
    'quit': lambda ctx: command_disconnect(ctx, True),
    'interrupt': lambda ctx: command_interrupt(ctx),
    'test': lambda ctx, scope: command_test(ctx, scope),
    'refresh': lambda ctx, verb: command_refresh(ctx, verb),
    'doc': lambda ctx: command_doc(ctx),
    'definition': lambda ctx: command_definition(ctx),
    'log-path': lambda ctx: 'set-option global nrepl_log_path ' + quote(paths_for(ctx.root)['log']),
}


def main():
    action, *args = sys.argv[1:]
    if action == 'daemon':
        return Daemon(args[0]).serve()
    if action == 'await-port':
        return await_port(*args)
    if action == 'test-report':
        return test_report(args[0], args[1], args[2], args[3], args[4:])
    if action == 'refresh-report':
        return refresh_report(*args)
    if action == 'complete':
        return complete(*args)
    if action == 'bb-server':
        return bb_server()
    handler = COMMANDS.get(action)
    if not handler:
        raise ValueError(f'unknown action {action!r}')
    try:
        print(handler(Context(), *args))
    except (OSError, ValueError) as error:
        print(fail(one_line(str(error))))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main() or 0)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
