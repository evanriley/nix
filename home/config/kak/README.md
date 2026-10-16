# Kakoune setup

Personal notes for this configuration. Not tracked in the dotfiles (listed in
`.git/info/exclude`).

## How the pieces fit

| Where | What | How it gets there |
|---|---|---|
| Global (your PATH) | `kak` only | `nix profile install path:~/sync/dotfiles/.config/kak` |
| Inside `kak` only | kak-lsp, kak-tree-sitter + grammars, parinfer-rust, the snippet server, plugins (auto-pairs, surround, rainbow) | bundled by `flake.nix`; the wrapper appends them to PATH for Kakoune and its children |
| Per project | compilers, REPLs, language servers (clojure-lsp, zls, gleam, rust-analyzer, ruff, …) | the project's own `flake.nix` + direnv |

Consequences:

- **Start `kak` from inside the project** (a shell where direnv has loaded). Kakoune
  inherits that PATH; that is how it finds clojure-lsp, bb, zls, etc.
- **One kak session per project.** A session started in project A does not see project
  B's tools. In tmux: one window per project, `kak` in each.
- Files outside any project (a scratch `.clj` in `/tmp`) get highlighting and editing,
  but no language server.
- Because the Kakoune wrapper *appends* its tools, a project's own version of a tool
  wins over the bundled one.

## Files

| File | Purpose |
|---|---|
| `kakrc` | options, highlighters, sources everything below, loads the darkman theme |
| `keys.kak` | **every mapping** — read this first |
| `editing.kak` | clipboard, move lines, surround, parinfer, rainbow |
| `tmux.kak` | splits, popups, terminal toggle (falls back to plain terminals outside tmux) |
| `pickers.kak`, `bin/kak-pick`, `bin/kak-tmux-popup` | fzf pickers in tmux popups |
| `explorer.kak` | oil-style directory buffer |
| `project.kak` | build/test/run commands per language, project root detection |
| `lsp.kak` | language servers, snippets server, formatting |
| `tree-sitter.kak` | kak-tree-sitter startup and face mapping |
| `repl.kak` | the `,` REPL layer: dispatches to nREPL or a tmux REPL pane |
| `nrepl.kak`, `nrepl.py` | Clojure nREPL client (daemon per project) |
| `ocaml.kak` | dune/opam/ocamllsp/utop |
| `support.py` | small helpers (build output, explorer, recent files, move lines) |
| `snippets/*.toml` | your own snippets (filename = language) |
| `flake.nix`, `flake.lock`, `nix/` | builds the editor and its tools; `nix/` holds a patch |

## Kakoune in five minutes (coming from Vim)

Kakoune is **selection first**: you select, then act. `w` *selects* a word, then `d`
deletes it (Vim's `dw` is Kakoune's `wd`).

- `x` select line (repeat to extend), `%` select whole buffer
- `s` split selection by regex → multiple cursors; `<a-s>` split on lines
- `<a-i>`/`<a-a>` inner/around objects: `<a-i>(`, `<a-a>"`, `<a-i>w`, `<a-i>p` (paragraph)
- `c` change, `d` delete, `y` yank, `p`/`P` paste, `u`/`U` undo/redo, `.` repeat insert
- `gg`/`ge` start/end, `gh`/`gl` line start/end, `<n>g` go to line n
- `/` search (case-insensitive here), `n`/`N` next/extend
- `;` collapse selection to cursor, `<space>,` keep only the main selection
  (Kakoune's own `,` is the local leader here)
- `:` command prompt, with completion; `:doc keys` for the full key list
- `q`/`Q` macros (`Q` records)
- Pressing a mode key and waiting shows what's available (like which-key), e.g. `<space>`, `,`, `g`

Useful docs from inside Kakoune: `:doc keys`, `:doc commands`, `:doc faq`.

## Keys

### `<space>` — general (mirrors the Neovim leader layout)

| Key | Action |
|---|---|
| `<space><space>` | find file (fzf popup with preview) |
| `/` | live grep the project; `*` grep for the selection |
| `b` | buffers, `o` recent files, `g` git files |
| `w` / `k` | write / kill buffer |
| `f` | format buffer |
| `e` | hover (type, docs, diagnostics at cursor) |
| `x` | project diagnostics list |
| `l` | kak-lsp's own menu (everything LSP) |
| `c` | code: `b` build, `t` test, `T` test file, `c` test at cursor, `r` run, `W` watch, `n`/`p` next/prev build error, `q` build output, `a` code action, `R` rename, `s`/`S` symbols, `e` expand selection, `w` trim whitespace, `C` load project `.kakrc` |
| `v` | toggles: `i` type hints, `d` line-end diagnostics, `f` format on save, `e` inline results, `p` parinfer, `r`/`R` rainbow |
| `s` | surround: `s` add, `c` change, `d` delete, `a` select, `t`/`T`/`D` tags |
| `t` | terminal pane (toggle; the shell survives hiding) |
| `G` | lazygit popup |
| `d` | git diff in the gutter |
| `p`/`P` | paste from the system clipboard (yanks go to it automatically) |
| `#` | comment lines |
| `,` | keep only the main selection |

### `,` — local leader (Conjure layout, same keys in every language)

| Key | Action |
|---|---|
| `ee` `er` `ew` `eb` `ef` | evaluate form / top-level form / word / buffer / file |
| `E` | evaluate the selection |
| `e!` | replace the form with its value |
| `ece` `ecr` `ecw` | append the value as a `;; =>` comment |
| `ei` | interrupt |
| `cc` | connect — **jack in** if no REPL is running |
| `cf` `cd` `cq` `cs` | connect to `.nrepl-port` / disconnect / disconnect and stop the jacked-in REPL / status |
| `ll` `ls` `lv` `lt` | log here / split below / split right / tmux window |
| `lq` `lr` | close log / clear log |
| `tt` (or `tc`) `tn` `ta` `tr` | test at cursor / namespace or file / all / rerun failures |
| `rr` `ra` `rc` | refresh changed / all namespaces / clear refresh tracker |
| `K` | docs (from the REPL when connected, else LSP) |
| `d` | go to definition (REPL when connected, else LSP) |
| `n` | set the evaluation namespace |

What `,` does per language:

| Language | Eval | Tests (`,t`) |
|---|---|---|
| Clojure | nREPL | nREPL (cider-nrepl ops if present, else `clojure.test` via eval); project `test_command` when disconnected |
| Python | text pasted into a REPL pane (`uv run python` / `ipython` / `python3`) | pytest (`-k name` at cursor) |
| OCaml | `dune utop` pane (`;;` added) | `dune runtest` |
| Zig, Rust, Gleam | none (says so) | `zig test --test-filter`, `cargo test name`, `gleam test` |

### Other mappings

- `-` — open the file explorer at the current file's directory
- `gd` `gr` `gy` `gI` — definition, references, type definition, implementation (LSP)
- `<a-up>` / `<a-down>` — move lines
- Insert mode: `<tab>`/`<s-tab>` walk the completion menu, `<ret>` accepts the selected
  item (expanding snippets), then `<tab>` jumps between snippet placeholders.
  With nothing selected, `<ret>` is a plain newline.

## Clojure workflow

1. `cd` into the project (direnv loads), `kak src/...`.
2. `,cc`. If `.nrepl-port` points at a live server, it connects. Otherwise it jacks in,
   choosing in order:
   - a `bb.edn` task named `nrepl`, or `dev`/`repl` whose doc mentions nREPL (the
     book's `bb dev`)
   - `deps.edn`: `clojure -Sdeps '{nrepl + cider-nrepl}' -M[:dev] -m nrepl.cmdline …`
   - `project.clj`: `lein … repl :headless`
   - `bb.edn` only: a Babashka nREPL
   The server runs in a tmux window named `nrepl` (switch to it to see its output).
   The modeline shows `nrepl:PORT` once connected.
3. Evaluate with `,ee`/`,er`; results show inline at the end of the form, in the echo
   area, and in a popup when long. Printed output goes to the log (`,ls`).
4. The first evaluation in a namespace loads that file's `ns` form automatically, so
   aliases work; `,eb` loads the whole buffer.
5. Tests: `,tt` on a `deftest`, `,tn` for the namespace (and its `-test` namespace),
   `,ta` for everything under `test/`. The code is saved and reloaded first. With
   cider-nrepl, failures land in the `*make*` buffer: `<space>cn` jumps to the next one.
6. `,cq` stops the REPL you jacked into; `,cd` just disconnects.

Override the jack-in command per project in `.kakrc` (see below):

```kak
set-option global nrepl_jack_in_command clojure -M:dev:nrepl
```

Notes: Babashka cannot interrupt a blocking call until it returns; a JVM REPL can.
The nREPL client keeps a small daemon per project (sockets and logs in
`$XDG_RUNTIME_DIR/kak-nrepl-$UID/`).

## Project setup

Give each project a flake with its toolchain **and its language server**, plus an
`.envrc` containing `use flake` (then `direnv allow`). Examples of what to include:

| Language | Packages |
|---|---|
| Clojure | `clojure`, `babashka`, `jdk21`, `clojure-lsp` |
| Zig | `zig`, `zls` (versions must match) |
| Gleam | `gleam`, `erlang`, `rebar3` (the gleam binary is also the language server and formatter) |
| Rust | `cargo`, `rustc`, `rust-analyzer`, `clippy`, `rustfmt` |
| Python | `python3`, `ruff`, optionally `basedpyright` and `pytest` (or use `uv`) |
| OCaml | via opam; the config runs `opam exec --` automatically |

Minimal Clojure flake shell:

```nix
devShells.default = pkgs.mkShell {
  packages = with pkgs; [ babashka clojure clojure-lsp jdk21 ];
};
```

Formatting on save uses the language server (clojure-lsp reads the project's
`cljfmt.edn`), except Zig (`zig fmt`) and Gleam (`gleam format`). Toggle per buffer with
`<space>vf`.

### Per-project overrides: `.kakrc`

Put a `.kakrc` in the project root and load it with `<space>cC` (not automatic, so
opening a random repo never runs its code). Useful options:

```kak
set-option global build_command make
set-option global test_command bb test
set-option global run_command bb main
set-option global test_cursor_command pytest {file} -k {name}
set-option global repl_command uv run ipython
set-option global nrepl_jack_in_command bb nrepl
set-option global format_on_save false
```

(`{file}` and `{name}` are filled in: the current file, and the test around the cursor.)

## File explorer

`-` opens the directory of the current file as a buffer. `<ret>` opens, `-` goes up,
`g.` toggles dotfiles. Edit it like text, then `:w`:

- change a line → rename (write `dir/` to move a file into an existing directory)
- delete a line → delete (to the trash via `gio`; refused on `/tmp`)
- add a line → create (end with `/` for a directory)

You get a summary to confirm (`y`) before anything happens.

## Snippets

Served by simple-completion-language-server through kak-lsp: friendly-snippets for
Python, Rust, Zig and Gleam (pinned by the flake) plus `snippets/<language>.toml`.
Clojure's are in `snippets/clojure.toml`. Format:

```toml
[[snippets]]
prefix = "defn"
body = "(defn ${1:name}\n  [${2:args}]\n  $0)"
description = "function"
```

Edits apply the next time the language servers start (`:lsp-restart` or a new session).

## Maintenance

**Updating everything** (Kakoune, kak-lsp, grammars, plugins, snippets):

```sh
cd ~/sync/dotfiles/.config/kak
nix flake update            # or: nix flake update helix  (just grammars/queries)
nix build --no-link .#      # check it builds
nix profile upgrade kak
```

Commit `flake.lock` afterwards. Running kak sessions keep the old build until
restarted; the first new session replaces the old tree-sitter server automatically.

**Config changes** take effect in new sessions. In a running one, `:source %val{config}/kakrc`
mostly works, but anything using `define-command` without `-override` will complain; a
restart is simplest.

**Adding a tree-sitter language**: add `kak-filetype = "helix-grammar-name";` to
`treeSitterLanguages` in `flake.nix` (Helix's `languages.toml` lists the grammar names),
then rebuild and upgrade. Queries that use Helix's `; inherits:` won't pick up the
inherited parts.

**Adding a language server**: add a `hook -group lsp-filetype-<ft> global BufSetOption
filetype=<ft>` block in `lsp.kak` (kak-lsp ships defaults for many languages already;
`~/.nix-profile/share/kak/bin/kak-lsp | less` shows them) and add the filetype to the snippet hook if you want
snippets there.

**Adding a plugin**: add it as a `flake = false` input and to `plugins` in `flake.nix`
via the `plugin` helper. Don't create `~/.config/kak/autoload/` — its presence stops
Kakoune from loading the flake's plugins and standard scripts.

**The snippet server patch** (`nix/scls-full-document-sync.patch`) makes it work with
kak-lsp, which sends whole documents and can skip `didOpen`. If an update changes that
code, the build fails at the patch step; refresh the patch against the new source.

**Uninstall**: `nix profile remove kak`.

## Troubleshooting

- **Something failed silently**: `:buffer *debug*` shows errors from hooks, kak-lsp
  and the language servers.
- **No language server**: is it on PATH in the shell you started kak from? (`:echo
  %sh{command -v clojure-lsp}`). `:lsp-restart` after fixing.
- **"unsupported offset encoding: utf-32"** in `*debug*`: harmless (snippet server).
- **nREPL stuck or confused**: `,cs` for status, `,cd` then `,cc` to reconnect. The
  daemon log is in `$XDG_RUNTIME_DIR/kak-nrepl-$UID/<project>-*.stderr`.
- **Stale `.nrepl-port`**: `,cc` removes it when nothing answers and jacks in again.
- **Pickers show Kakoune's prompt instead of fzf**: not inside tmux, or no tmux client
  attached.
- **Highlighting looks plain for a language**: it isn't in `treeSitterLanguages`, so
  Kakoune's built-in highlighter is used (that's intended).
- **Theme**: darkman writes `~/.local/state/darkman/monobiome-alpine.kak` and re-sources
  it in running sessions when the mode changes.
