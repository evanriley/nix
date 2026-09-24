#!/usr/bin/env python3
"""Small helpers for the Kakoune configuration (the nREPL client lives in nrepl.py)."""
import difflib
import fcntl
import glob
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


def quote(text):
    return "'" + str(text).replace("'", "''") + "'"


def root_for(filename, markers):
    start = Path(filename).absolute().parent if filename else Path.cwd()
    for directory in (start, *start.parents):
        if any(glob.glob(str(directory / marker)) for marker in markers):
            return directory
    return start


def line_plan(descriptions, count, direction):
    selections = [[list(map(int, end.split('.'))) for end in desc.split(',')]
                  for desc in descriptions.split()]
    ranges = sorted((min(a[0], b[0]), max(a[0], b[0])) for a, b in selections)
    blocks = []
    for start, end in ranges:
        if blocks and start <= blocks[-1][1] + 1:
            blocks[-1][1] = max(end, blocks[-1][1])
        else:
            blocks.append([start, end])
    movable = [(a, b) for a, b in blocks if (a > 1 if direction < 0 else b < count)]
    for selection in selections:
        if any(a <= selection[0][0] <= b for a, b in movable):
            for endpoint in selection:
                endpoint[0] += direction
    return movable, selections


def move_lines(direction, descriptions, count, output):
    blocks, selections = line_plan(descriptions, count, direction)
    if output == 'select':
        print('select ' + ' '.join(','.join(f'{a}.{b}' for a, b in s) for s in selections))
        return
    data = sys.stdin.buffer.read()
    parts = data.split(b'\n')
    lines = [line + b'\n' for line in parts[:-1]]
    if parts[-1]:
        lines.append(parts[-1])
    for start, end in (blocks if direction < 0 else reversed(blocks)):
        if direction < 0:
            lines[start-2:end] = lines[start-1:end] + lines[start-2:start-1]
        else:
            lines[start-1:end+1] = lines[end:end+1] + lines[start-1:end]
    sys.stdout.buffer.write(b''.join(lines))


def recent(path, filename, limit):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(str(path) + '.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        old = path.read_text().splitlines() if path.exists() else []
        entries = list(dict.fromkeys([filename, *old]))[:max(1, limit)]
        fd, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
        try:
            with os.fdopen(fd, 'w') as stream:
                stream.write('\n'.join(entries) + '\n')
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
OCAML = re.compile(r'^File "([^"]+)", lines? (\d+)(?:-\d+)?, characters (\d+)-\d+:')
PANIC = re.compile(r"^thread '([^']*)'.* panicked at ([^:\s]+):(\d+):(\d+):")
LOCATION = re.compile(r'^\s*(?:--> )?([^\s:][^:]*?):(\d+)(?::(\d+))?(?::|\s|$)\s*(.*)')


def normalize(line, root, severity='error', context=''):
    """Rewrite compiler locations as absolute file:line:col: error: … so *make* can jump."""
    line = ANSI.sub('', line)
    match = OCAML.match(line)
    if match:
        filename, row, col = match.groups()
        return f'{(Path(root) / filename).resolve()}:{row}:{int(col)+1}: error: OCaml diagnostic\n'
    match = PANIC.match(line)
    if match and (Path(root) / match[2]).is_file():
        thread, filename, row, col = match.groups()
        return f'{(Path(root) / filename).resolve()}:{row}:{col}: error: {thread} panicked\n'
    match = LOCATION.match(line)
    # Only the project's own files are jump targets; library frames stay plain text.
    if match and (Path(root) / match[1]).is_file() and \
            (Path(root) / match[1]).resolve().is_relative_to(Path(root).resolve()):
        filename, row, col, message = match.groups()
        if not re.match(r'(fatal )?(error|warning|note)\b', message):
            message = f'{severity}: {message or context}'
        return f'{(Path(root) / filename).resolve()}:{row}:{col or 1}: {message}\n'
    return line


def build(root, command):
    print('$ ' + shlex.join(command), flush=True)
    env = dict(os.environ, NO_COLOR='1', TERM='dumb', CARGO_TERM_COLOR='never')
    try:
        process = subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, errors='replace')
    except OSError as error:
        print(f'{command[0]}: {error.strerror}; is it on PATH in this project shell?')
        print('\n[exit 127]', flush=True)
        return 127
    severity, context = 'error', ''
    for line in process.stdout:
        # Rust puts the location on the line after an error:/warning: header.
        header = re.match(r'\s*(error|warning|note)(?:\[\w+\])?:\s*(.*)', ANSI.sub('', line))
        if header:
            severity, context = header[1], header[2].strip()
        print(normalize(line, root, severity, context), end='', flush=True)
    status = process.wait()
    print(f'\n[exit {status}]', flush=True)
    return status


def grep_open(root, choice):
    match = re.match(r'^(.+?):([1-9]\d*):([1-9]\d*):', choice)
    if not match:
        print('fail ' + quote('select a grep result from the menu'))
        return
    filename, row, col = match.groups()
    print(f'edit -existing {quote(Path(root) / filename)} {row} {col}')


# Explorer ----------------------------------------------------------------------------------

def explorer_list(directory, hidden):
    entries = []
    for entry in os.scandir(directory):
        if hidden != 'true' and entry.name.startswith('.'):
            continue
        is_dir = entry.is_dir(follow_symlinks=True)
        entries.append((not is_dir, entry.name.lower(), entry.name + ('/' if is_dir else '')))
    sys.stdin.read()
    print('\n'.join(name for *_, name in sorted(entries)))


def explorer_plan(directory, quoted_entries, text):
    old = shlex.split(quoted_entries)
    new = [line.strip() for line in text.split('\n') if line.strip()]
    operations = []
    base = Path(directory)

    def pairs(name, target):
        into_directory = target.endswith('/') and (base / target).is_dir()
        return name.endswith('/') == target.endswith('/') or into_directory

    matcher = difflib.SequenceMatcher(a=old, b=new, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        removed, added = old[i1:i2], new[j1:j2]
        if tag == 'equal':
            continue
        # A changed line is a rename when it stays a file (or a directory); the rest of
        # the block is deletions and creations. The summary is confirmed before anything runs.
        pending = list(added)
        for name in removed:
            partner = next((b for b in pending if pairs(name, b)), None)
            if partner is None:
                operations.append(['delete', name])
            else:
                pending.remove(partner)
                operations.append(['move', name, partner])
        operations += [['create', name] for name in pending]
    if not operations:
        print("echo 'explorer: nothing to change'")
        return
    problems, lines = [], []
    for operation in operations:
        kind, name = operation[0], operation[1]
        if kind == 'move':
            target = operation[2]
            destination = base / target.rstrip('/')
            if target.endswith('/') and not name.endswith('/') and destination.is_dir():
                destination = destination / name
            if destination.exists():
                problems.append(f'{target} already exists')
            lines.append(f'  move    {name} -> {os.path.relpath(destination, base)}')
            operation[2] = str(destination)
        elif kind == 'delete':
            lines.append(f'  delete  {name}')
        else:
            if (base / name.rstrip('/')).exists():
                problems.append(f'{name} already exists')
            lines.append(f'  create  {name}')
    if problems:
        print('fail ' + quote('explorer: ' + '; '.join(problems)))
        return
    trash = 'to the trash' if shutil.which('gio') else 'permanently'
    summary = f'{directory}\n\n' + '\n'.join(lines) + (
        f'\n\ndeletions go {trash}' if any(op[0] == 'delete' for op in operations) else '')
    plan = json.dumps({'directory': directory, 'operations': operations})
    print('set-option buffer explorer_plan ' + quote(plan))
    print('info -title ' + quote('apply these changes?') + ' -- ' + quote(summary))
    print("prompt 'apply? (y/n) ' %{ evaluate-commands %sh{ [ \"$kak_text\" = y ] && echo explorer-apply || echo explorer-fill } }")


def explorer_apply(plan):
    plan = json.loads(plan)
    base = Path(plan['directory'])
    done, failures = 0, []
    for operation in plan['operations']:
        kind, name = operation[0], operation[1]
        source = base / name.rstrip('/')
        try:
            if kind == 'move':
                destination = Path(operation[2])
                destination.parent.mkdir(parents=True, exist_ok=True)
                source.rename(destination)
            elif kind == 'delete':
                if shutil.which('gio'):
                    subprocess.run(['gio', 'trash', '--', str(source)], check=True,
                                   capture_output=True)
                elif source.is_dir() and not source.is_symlink():
                    shutil.rmtree(source)
                else:
                    source.unlink()
            elif name.endswith('/'):
                source.mkdir(parents=True)
            else:
                source.parent.mkdir(parents=True, exist_ok=True)
                source.touch(exist_ok=False)
            done += 1
        except (OSError, subprocess.CalledProcessError) as error:
            failures.append(f'{kind} {name}: {getattr(error, "strerror", None) or error}')
    if failures:
        print('echo -markup ' + quote('{Error}explorer: ' + '; '.join(failures)))
    else:
        print('echo ' + quote(f'explorer: applied {done} changes'))


def main():
    action, *args = sys.argv[1:]
    if action == 'root':
        print(root_for(os.environ.get('kak_buffile', ''), shlex.split(args[0])))
    elif action == 'move':
        move_lines(int(args[0]), args[1], int(args[2]), args[3])
    elif action == 'recent':
        recent(args[0], args[1], int(args[2]))
    elif action == 'build':
        return build(args[0], args[1:])
    elif action == 'grep-open':
        grep_open(*args)
    elif action == 'explorer-list':
        explorer_list(*args)
    elif action == 'explorer-plan':
        explorer_plan(*args)
    elif action == 'explorer-apply':
        explorer_apply(*args)
    else:
        raise ValueError(f'unknown action {action!r}')


if __name__ == '__main__':
    try:
        sys.exit(main() or 0)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
