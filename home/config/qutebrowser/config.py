import os
import pathlib
import re
import sys

config.load_autoconfig(False)
c.auto_save.session = True

c.qt.force_software_rendering = 'none'
c.qt.args = ['disable-features=AcceleratedVideoDecodeLinuxZeroCopyGL']

c.url.searchengines = {
    'DEFAULT': 'https://kagi.com/search?q={}',
    'g':  'https://google.com/search?q={}',
    'aw': 'https://wiki.archlinux.org/?search={}',
    'yt': 'https://www.youtube.com/results?search_query={}',
    'gh': 'https://github.com/search?q={}'
}
c.url.default_page = 'https://kagi.com'
c.url.start_pages = ['https://kagi.com']
c.url.open_base_url = True

c.window.transparent = False

c.tabs.position = 'left'
c.tabs.width = 240
c.tabs.padding = {'top': 10, 'bottom': 10, 'left': 5, 'right': 5}
c.tabs.indicator.width = 0
c.tabs.favicons.scale = 1.0
c.tabs.title.format = '{audio}{index}: {current_title}'
c.tabs.show = 'never'

c.statusbar.show = 'in-mode'
c.statusbar.padding = {'top': 5, 'bottom': 5, 'left': 5, 'right': 5}
c.statusbar.widgets = ['keypress', 'url', 'scroll', 'history', 'tabs', 'progress']

c.content.user_stylesheets = [str(config.configdir / 'youtube.css')]

PALETTE_FILE = (
    pathlib.Path(os.environ.get('XDG_CONFIG_HOME') or pathlib.Path.home()
                 / '.config') / 'theme' / 'qutebrowser.conf'
)
PALETTE_KEYS = frozenset({
    'bg', 'bg_alt', 'bg_soft', 'selection', 'border', 'muted', 'fg', 'fg_alt',
    'blue', 'green', 'green_alt', 'magenta', 'yellow', 'yellow_bright', 'red',
    'rust',
})
HEX_COLOR = re.compile(r'#[0-9a-fA-F]{6}')
FALLBACK_MODE = 'dark'


def load_palette(path):
    """Read the generated palette, or None when it is unusable.

    Absent, unreadable, half-written and malformed files all yield None so
    that qutebrowser still starts -- notably before home-manager has generated
    it. Validation is strict because a partial palette would paint an
    unreadable mix of the two modes.
    """
    try:
        text = path.read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError):
        return None
    palette = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        key, separator, value = line.partition('=')
        if not separator:
            return None
        palette[key.strip()] = value.strip()
    if palette.get('mode') not in ('light', 'dark'):
        return None
    if not PALETTE_KEYS <= palette.keys():
        return None
    if not all(HEX_COLOR.fullmatch(palette[key]) for key in PALETTE_KEYS):
        return None
    return palette


def apply_palette(p):
    c.colors.tabs.bar.bg = p['bg']

    c.colors.tabs.odd.bg = p['bg']
    c.colors.tabs.even.bg = p['bg']
    c.colors.tabs.odd.fg = p['muted']
    c.colors.tabs.even.fg = p['muted']

    c.colors.tabs.selected.odd.bg = p['selection']
    c.colors.tabs.selected.even.bg = p['selection']
    c.colors.tabs.selected.odd.fg = p['fg']
    c.colors.tabs.selected.even.fg = p['fg']

    c.colors.tabs.pinned.even.bg = p['selection']
    c.colors.tabs.pinned.odd.bg = p['selection']
    c.colors.tabs.pinned.even.fg = p['fg_alt']
    c.colors.tabs.pinned.odd.fg = p['fg_alt']
    c.colors.tabs.pinned.selected.even.bg = p['selection']
    c.colors.tabs.pinned.selected.odd.bg = p['selection']
    c.colors.tabs.pinned.selected.even.fg = p['fg']
    c.colors.tabs.pinned.selected.odd.fg = p['fg']
    c.colors.tabs.indicator.start = p['blue']
    c.colors.tabs.indicator.stop = p['green_alt']
    c.colors.tabs.indicator.error = p['red']

    c.colors.statusbar.normal.bg = p['bg_alt']
    c.colors.statusbar.normal.fg = p['fg']
    c.colors.statusbar.insert.bg = p['blue']
    c.colors.statusbar.insert.fg = p['bg']
    c.colors.statusbar.command.bg = p['selection']
    c.colors.statusbar.command.fg = p['fg']
    c.colors.statusbar.command.private.bg = p['selection']
    c.colors.statusbar.command.private.fg = p['magenta']
    c.colors.statusbar.caret.bg = p['magenta']
    c.colors.statusbar.caret.fg = p['bg']
    c.colors.statusbar.caret.selection.bg = p['rust']
    c.colors.statusbar.caret.selection.fg = p['bg']
    c.colors.statusbar.passthrough.bg = p['yellow']
    c.colors.statusbar.passthrough.fg = p['bg']
    c.colors.statusbar.private.bg = p['bg_soft']
    c.colors.statusbar.private.fg = p['magenta']
    c.colors.statusbar.progress.bg = p['blue']
    c.colors.statusbar.url.error.fg = p['red']
    c.colors.statusbar.url.hover.fg = p['magenta']
    c.colors.statusbar.url.warn.fg = p['yellow_bright']
    c.colors.statusbar.url.success.http.fg = p['muted']
    c.colors.statusbar.url.success.https.fg = p['green']

    c.colors.hints.bg = p['yellow_bright']
    c.colors.hints.fg = p['bg']
    c.colors.hints.match.fg = p['red']

    c.colors.completion.category.bg = p['bg']
    c.colors.completion.category.fg = p['fg_alt']
    c.colors.completion.category.border.top = p['border']
    c.colors.completion.category.border.bottom = p['border']
    c.colors.completion.odd.bg = p['bg']
    c.colors.completion.even.bg = p['bg_alt']
    c.colors.completion.fg = p['fg']
    c.colors.completion.item.selected.bg = p['selection']
    c.colors.completion.item.selected.fg = p['fg']
    c.colors.completion.item.selected.border.top = p['selection']
    c.colors.completion.item.selected.border.bottom = p['selection']
    c.colors.completion.match.fg = p['magenta']
    c.colors.completion.item.selected.match.fg = p['rust']
    c.colors.completion.scrollbar.bg = p['bg_alt']
    c.colors.completion.scrollbar.fg = p['fg_alt']

    c.colors.prompts.bg = p['bg_alt']
    c.colors.prompts.fg = p['fg']
    c.colors.prompts.border = '1px solid ' + p['border']
    c.colors.prompts.selected.bg = p['selection']
    c.colors.prompts.selected.fg = p['fg']
    c.colors.messages.info.bg = p['bg_alt']
    c.colors.messages.info.border = p['blue']
    c.colors.messages.info.fg = p['fg']
    c.colors.messages.warning.bg = p['bg_alt']
    c.colors.messages.warning.border = p['yellow_bright']
    c.colors.messages.warning.fg = p['yellow_bright']
    c.colors.messages.error.bg = p['bg_alt']
    c.colors.messages.error.border = p['red']
    c.colors.messages.error.fg = p['red']
    c.colors.keyhint.bg = p['bg_alt']
    c.colors.keyhint.fg = p['fg']
    c.colors.keyhint.suffix.fg = p['rust']
    c.colors.downloads.bar.bg = p['bg']
    c.colors.downloads.start.bg = p['blue']
    c.colors.downloads.start.fg = p['bg']
    c.colors.downloads.stop.bg = p['green']
    c.colors.downloads.stop.fg = p['bg']
    c.colors.downloads.error.bg = p['red']
    c.colors.downloads.error.fg = p['bg']

    c.colors.webpage.bg = p['bg']


_palette = load_palette(PALETTE_FILE)
# Without a palette the stock qutebrowser colors stand; forced page darkening
# still needs a mode, and dark is the safer guess for an unthemed session.
mode = _palette['mode'] if _palette is not None else FALLBACK_MODE
c.colors.webpage.preferred_color_scheme = mode
if _palette is not None:
    apply_palette(_palette)

c.scrolling.bar = 'never'
c.fonts.default_family = _palette.get('font', 'monospace') if _palette is not None else 'monospace'
c.fonts.default_size = "12pt"
c.fonts.web.size.default = 16

c.downloads.position = 'bottom'
c.downloads.remove_finished = 5000
c.downloads.location.suggestion = 'both'
c.downloads.location.prompt = False
c.downloads.location.directory = '~/Downloads'

c.completion.open_categories = ['history', 'quickmarks', 'bookmarks',
                                'searchengines', 'filesystem']

try:
    from qutebrowser.misc import sql as _sql

    _FRECENCY = """(SELECT SUM(CASE
        WHEN h.atime > strftime('%s','now') - 345600  THEN 100
        WHEN h.atime > strftime('%s','now') - 1209600 THEN 70
        WHEN h.atime > strftime('%s','now') - 2678400 THEN 50
        WHEN h.atime > strftime('%s','now') - 7776000 THEN 30
        ELSE 10 END)
      FROM History h
      WHERE h.url = CompletionHistory.url AND NOT h.redirect)"""

    _STOCK_ORDER = 'ORDER BY last_atime DESC'
    _orig_query = _sql.Database.query

    if not getattr(_orig_query, '_frecency_patched', False):
        _index_done = []

        def _frecency_query(self, querystr, forward_only=True):
            # Only the completion query itself. The max_items subquery in
            # _atime_expr() also selects from CompletionHistory with the same
            # ORDER BY and must be left alone; it does not select url, title.
            if querystr.startswith('SELECT url, title,') and _STOCK_ORDER in querystr:
                try:
                    if not _index_done:
                        _orig_query(self, 'CREATE INDEX IF NOT EXISTS '
                                          'HistoryIndex ON History (url)').run()
                        _index_done.append(True)
                except Exception:
                    # A locked or read-only history database would otherwise
                    # raise into the completion itself. Recency also happens
                    # to be the right fallback: without the index the frecency
                    # sort is a full table scan per candidate row.
                    pass
                else:
                    querystr = querystr.replace(
                        _STOCK_ORDER,
                        'ORDER BY {} DESC, last_atime DESC'.format(_FRECENCY))
            return _orig_query(self, querystr, forward_only)

        _frecency_query._frecency_patched = True
        _sql.Database.query = _frecency_query
except Exception:
    pass
c.tabs.last_close = 'startpage'
c.tabs.mode_on_change = 'restore'
c.confirm_quit = ['downloads']
c.spellcheck.languages = ['en-US']

c.scrolling.smooth = False
c.qt.chromium.process_model = 'process-per-site'
c.content.autoplay = False
c.content.pdfjs = True
c.session.lazy_restore = True
c.content.blocking.method = 'both'
c.content.blocking.adblock.lists = [
    "https://easylist.to/easylist/easylist.txt",
    "https://easylist.to/easylist/easyprivacy.txt",
    "https://ublockorigin.github.io/uAssets/filters/filters.txt",
    "https://ublockorigin.github.io/uAssets/filters/badware.txt",
    "https://ublockorigin.github.io/uAssets/filters/privacy.txt",
    "https://ublockorigin.github.io/uAssets/filters/quick-fixes.txt",
    "https://ublockorigin.github.io/uAssets/filters/unbreak.txt",
    "https://pgl.yoyo.org/adservers/serverlist.php"
    "?hostformat=adblockplus&showintro=0&mimetype=plaintext",
]
c.content.blocking.whitelist = [
    'https://challenges.cloudflare.com/*',
    '*://*/akam/*',
]

c.content.tls.certificate_errors = 'block'

c.content.desktop_capture = False
c.content.geolocation = False
c.content.media.audio_capture = False
c.content.media.audio_video_capture = False
c.content.media.video_capture = False
c.content.mouse_lock = False
c.content.notifications.enabled = False
c.content.persistent_storage = False
c.content.register_protocol_handler = False


c.content.javascript.log_message.excludes['userscript:_qute_js'] = [
    '*TrustedHTML*',
]

# --- QT 6.11 SCRIPT-INJECTION WORKAROUND ---
# QtWebEngine 6.11 sometimes drops the DocumentCreation injection of
# qutebrowser's own JavaScript; a redirecting URL opened in a new tab
# (':open -t http://duckduckgo.com') reproduces it. window._qutebrowser is then
# undefined in the application world, so 'f' fails with "Unknown error while
# getting elements" and j/k, <Ctrl-d>/<Ctrl-u> and caret mode stay dead until
# the tab is reloaded. Upstream: qutebrowser#8925, fix pending in #8940.
#
# find_css is the only affected path that reports an error, so it is the hook:
# on that specific failure the bundle is re-evaluated into the application
# world and the lookup retried once. Scrolling and caret mode come back with
# it, since the whole bundle is restored.
#
# Both steps are posted to the event loop. A runJavaScript issued from inside
# a runJavaScript callback never has its result delivered.
#
# stylesheet.js is deliberately left out of the bundle: injecting it here
# never returns, and user stylesheets do not error out visibly anyway.
#
# WebEngineElements is imported after config.py runs, and configfiles.py drops
# every module config.py imports back out of sys.modules, so the class cannot
# be reached directly. __init_subclass__ on its already-imported base catches
# the class as it is defined instead.
try:
    from qutebrowser.browser import browsertab as _browsertab
    from qutebrowser.utils import resources as _resources
    from qutebrowser.qt.core import QTimer as _QTimer

    _MISSING = 'Unknown error while getting elements'

    def _reinject_code():
        return ('(function() {{ "use strict";\n'
                'if (!window.hasOwnProperty("_qutebrowser")) {{'
                ' window._qutebrowser = {{"initialized": {{}}}}; }}\n'
                '{}\n'
                'window._qutebrowser.initialized["scripts"] = true;\n'
                '}})();').format('\n'.join(
                    _resources.read_file('javascript/' + name)
                    for name in ('scroll.js', 'webelem.js', 'caret.js')))

    def _patch_elements(cls):
        if getattr(cls.find_css, '_reinjects', False):
            return
        orig = cls.find_css

        def find_css(self, selector, callback, error_cb, *,
                     only_visible=False, _retry=True):
            def on_error(err):
                if not (_retry and _MISSING in str(err)):
                    error_cb(err)
                    return

                def retry():
                    find_css(self, selector, callback, error_cb,
                             only_visible=only_visible, _retry=False)

                def reinject():
                    self._tab.run_js_async(_reinject_code())
                    _QTimer.singleShot(0, retry)

                _QTimer.singleShot(0, reinject)

            orig(self, selector, callback, on_error, only_visible=only_visible)

        find_css._reinjects = True
        cls.find_css = find_css

    def _on_subclass(cls, **kwargs):
        super(_browsertab.AbstractElements, cls).__init_subclass__(**kwargs)
        if cls.__name__ == 'WebEngineElements':
            _patch_elements(cls)

    _browsertab.AbstractElements.__init_subclass__ = classmethod(_on_subclass)
    for _sub in _browsertab.AbstractElements.__subclasses__():
        if _sub.__name__ == 'WebEngineElements':
            _patch_elements(_sub)
except Exception:
    pass

config.bind('M', 'hint links userscript qute-mpv')
config.bind('xm', 'spawn --userscript qute-mpv')

config.bind('<Space>pl', 'spawn --userscript qute-bitwarden')
config.bind('<Space>pu', 'spawn --userscript qute-bitwarden --username-only')
config.bind('<Space>pp', 'spawn --userscript qute-bitwarden --password-only')
config.bind('<Space>pL', 'spawn --userscript qute-bitwarden --lock')

config.bind('J', 'tab-next')
config.bind('K', 'tab-prev')
config.bind('T', 'config-cycle tabs.show always never')
config.bind(';r', 'hint --rapid links tab-bg')
config.bind('m', 'quickmark-save')
config.bind('b', 'cmd-set-text -s :quickmark-load')
config.bind('B', 'cmd-set-text -s :quickmark-load -t')
config.bind('ss', 'open -t {primary}')

if sys.platform == 'darwin':
    # open -W returns once Ghostty quits, so it must quit with its last window.
    terminal = [
        'open', '-W', '-n', '-a', 'Ghostty', '--args',
        '--quit-after-last-window-closed=true', '-e',
    ]
else:
    terminal = ['foot', '--app-id=qute-editor']
c.editor.command = terminal + [
    'nvim', '-f', '{file}',
    '-c', 'call cursor({line}, {column})',
]

c.colors.webpage.darkmode.enabled = mode == 'dark'
c.colors.webpage.darkmode.algorithm = 'lightness-cielab'
c.colors.webpage.darkmode.policy.images = 'smart'

darkmode_native_sites = [
    '*://*.youtube.com/*',
    '*://*.discord.com/*',
    '*://*.fastmail.com/*',
    '*://*.codeberg.org/*',
    '*://*.crates.io/*',
]
for _pattern in darkmode_native_sites:
    config.set('colors.webpage.darkmode.enabled', False, _pattern)

config.bind(
    '<Space>td',
    'config-cycle -t -p -u *://{url:host}/* colors.webpage.darkmode.enabled'
    ' false true ;; reload',
)

c.content.cookies.accept = 'no-3rdparty'
c.content.headers.referer = 'same-domain'
c.content.canvas_reading = True

c.hints.chars = 'asdfghjkl'

config.bind('yy', 'spawn --userscript qute-cleanurl')
config.bind('yr', 'yank')
config.bind('yt', 'spawn --userscript qute-cleanurl --markdown')
