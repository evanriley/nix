# Every mapping lives here.
#   <space>  general (mirrors the Neovim leader layout)
#   ,        local leader: REPL, tests, docs; same keys in every language (Conjure layout)
# Kakoune's own , (keep only the main selection) moves to <space>,.

# Normal mode --------------------------------------------------------------------------------

map global normal / '/(?i)' -docstring 'search (case-insensitive)'
map global normal <a-/> '<a-/>(?i)' -docstring 'search backward (case-insensitive)'
map global normal ? '?(?i)' -docstring 'extend search (case-insensitive)'
map global normal <a-?> '<a-?>(?i)' -docstring 'extend search backward (case-insensitive)'

map global normal <minus> ': explorer<ret>' -docstring 'browse the current directory'
map global normal <a-down> ': move-lines 1<ret>' -docstring 'move lines down'
map global normal <a-up> ': move-lines -1<ret>' -docstring 'move lines up'
map global normal , ': enter-user-mode local<ret>' -docstring 'local leader…'

map global goto d '<esc>: lsp-definition<ret>' -docstring 'definition'
map global goto r '<esc>: lsp-references<ret>' -docstring 'references'
map global goto y '<esc>: lsp-type-definition<ret>' -docstring 'type definition'
map global goto I '<esc>: lsp-implementation<ret>' -docstring 'implementation'

# Insert mode ------------------------------------------------------------------------------
# <tab>/<s-tab> walk the completion menu and <ret> accepts the selected candidate (expanding
# a snippet); with no menu, <tab> jumps to the next snippet placeholder.

map global insert <tab> '<a-;>: try lsp-snippets-select-next-placeholders catch %{ execute-keys -with-hooks <lt>tab> }<ret>' \
    -docstring 'next snippet placeholder'

# Completion items run this when selected; closing the menu accepts without a newline.
define-command -hidden completion-selected %{ map window insert <ret> <c-o><c-o> }

# kak-lsp's own selection hook (same body), plus completion-selected.
define-command -override -hidden lsp-completion-item-selected -params 1 %{
    set-option window lsp_completions_selected_item %arg{1}
    remove-hooks window lsp-completion-accepted
    completion-selected
}

hook global InsertCompletionShow .* %{
    map window insert <tab> <c-n>
    map window insert <s-tab> <c-p>
    hook -once -always window InsertCompletionHide .* %{
        unmap window insert <tab> <c-n>
        unmap window insert <s-tab> <c-p>
        unmap window insert <ret>
    }
}

# <space> -----------------------------------------------------------------------------------

map global user <space> ': picker-files<ret>' -docstring 'find files'
map global user / ': picker-grep<ret>' -docstring 'grep the project'
map global user * ': picker-grep-word<ret>' -docstring 'grep for the selection'
map global user b ': picker-buffers<ret>' -docstring 'buffers'
map global user o ': picker-recent<ret>' -docstring 'recent files'
map global user g ': picker-git<ret>' -docstring 'git files'
map global user w ': write<ret>' -docstring 'write'
map global user k ': delete-buffer<ret>' -docstring 'kill buffer'
map global user , ',' -docstring 'keep only the main selection'
map global user '#' ': comment-line<ret>' -docstring 'comment lines'
map global user p ': clipboard-paste p<ret>' -docstring 'paste clipboard after'
map global user P ': clipboard-paste P<ret>' -docstring 'paste clipboard before'
map global user f ': code-format<ret>' -docstring 'format buffer'
map global user e ': lsp-hover<ret>' -docstring 'hover: type, docs, diagnostics'
map global user x ': lsp-diagnostics<ret>' -docstring 'project diagnostics'
map global user l ': enter-user-mode lsp<ret>' -docstring 'lsp…'
map global user c ': enter-user-mode code<ret>' -docstring 'code: build, test, refactor…'
map global user v ': enter-user-mode toggles<ret>' -docstring 'toggles…'
map global user s ': enter-user-mode surround<ret>' -docstring 'surround…'
map global user t ': terminal-toggle<ret>' -docstring 'terminal'
map global user G ': tmux-popup lazygit<ret>' -docstring 'lazygit'
map global user d ': git show-diff<ret>' -docstring 'show git diff in the gutter'

declare-user-mode code
map global code b ': build<ret>' -docstring 'build'
map global code t ': test<ret>' -docstring 'test the project'
map global code T ': test-file<ret>' -docstring 'test this file'
map global code c ': test-cursor<ret>' -docstring 'test at the cursor'
map global code r ': run<ret>' -docstring 'run (pane)'
map global code W ': watch<ret>' -docstring 'watch (pane)'
map global code n ': make-next-error<ret>' -docstring 'next build error'
map global code p ': make-previous-error<ret>' -docstring 'previous build error'
map global code q ': buffer *make*<ret>' -docstring 'build output'
map global code a ': lsp-code-actions<ret>' -docstring 'code actions'
map global code R ': lsp-rename-prompt<ret>' -docstring 'rename symbol'
map global code s ': lsp-document-symbol<ret>' -docstring 'document symbols'
map global code S ': lsp-workspace-symbol-incr<ret>' -docstring 'workspace symbols'
map global code e ': lsp-selection-range<ret>' -docstring 'expand selection by syntax'
map global code w ': trim-whitespace<ret>' -docstring 'trim trailing whitespace'
map global code C ': project-config<ret>' -docstring 'load the project .kakrc'

declare-user-mode toggles
map global toggles i ': toggle-inlay-hints<ret>' -docstring 'type hints'
map global toggles d ': toggle-inlay-diagnostics<ret>' -docstring 'diagnostics at line ends'
map global toggles f ': toggle-format-on-save<ret>' -docstring 'format on save (buffer)'
map global toggles e ': toggle-eval-results<ret>' -docstring 'inline evaluation results'
map global toggles p ': parinfer-toggle<ret>' -docstring 'parinfer'
map global toggles r ': rainbow-enable-window<ret>' -docstring 'rainbow delimiters on'
map global toggles R ': rainbow-disable-window<ret>' -docstring 'rainbow delimiters off'

# , local leader ----------------------------------------------------------------------------

declare-user-mode local
declare-user-mode local-eval
declare-user-mode local-eval-comment
declare-user-mode local-connect
declare-user-mode local-log
declare-user-mode local-test
declare-user-mode local-refresh

map global local e ': enter-user-mode local-eval<ret>' -docstring 'evaluate…'
map global local E ': repl eval selection<ret>' -docstring 'evaluate the selection'
map global local c ': enter-user-mode local-connect<ret>' -docstring 'connection…'
map global local l ': enter-user-mode local-log<ret>' -docstring 'log…'
map global local t ': enter-user-mode local-test<ret>' -docstring 'tests…'
map global local r ': enter-user-mode local-refresh<ret>' -docstring 'refresh namespaces…'
map global local K ': repl-doc<ret>' -docstring 'documentation'
map global local d ': repl-definition<ret>' -docstring 'definition'
map global local n ': repl set-namespace<ret>' -docstring 'set the evaluation namespace'

map global local-eval e ': repl eval form<ret>' -docstring 'form around the cursor'
map global local-eval r ': repl eval root<ret>' -docstring 'top-level form'
map global local-eval w ': repl eval word<ret>' -docstring 'word'
map global local-eval b ': repl eval buffer<ret>' -docstring 'buffer'
map global local-eval f ': repl eval file<ret>' -docstring 'file (as saved)'
map global local-eval ! ': repl eval-replace<ret>' -docstring 'replace the form with its value'
map global local-eval i ': repl interrupt<ret>' -docstring 'interrupt'
map global local-eval c ': enter-user-mode local-eval-comment<ret>' -docstring 'value as a comment…'

map global local-eval-comment e ': repl eval-comment form<ret>' -docstring 'form'
map global local-eval-comment r ': repl eval-comment root<ret>' -docstring 'top-level form'
map global local-eval-comment w ': repl eval-comment word<ret>' -docstring 'word'

map global local-connect c ': repl jack-in<ret>' -docstring 'connect, starting the REPL if needed'
map global local-connect f ': repl connect<ret>' -docstring 'connect to .nrepl-port'
map global local-connect d ': repl disconnect<ret>' -docstring 'disconnect'
map global local-connect q ': repl quit<ret>' -docstring 'disconnect and stop the REPL'
map global local-connect s ': repl status<ret>' -docstring 'status'

map global local-log l ': repl log here<ret>' -docstring 'in this window'
map global local-log s ': repl log below<ret>' -docstring 'split below'
map global local-log v ': repl log right<ret>' -docstring 'split right'
map global local-log t ': repl log window<ret>' -docstring 'new tmux window'
map global local-log q ': repl log close<ret>' -docstring 'close'
map global local-log r ': repl log reset<ret>' -docstring 'clear'

map global local-test c ': repl-test cursor<ret>' -docstring 'test at the cursor'
map global local-test t ': repl-test cursor<ret>' -docstring 'test at the cursor'
map global local-test n ': repl-test namespace<ret>' -docstring 'namespace / file'
map global local-test a ': repl-test all<ret>' -docstring 'all tests'
map global local-test r ': repl-test rerun<ret>' -docstring 'rerun failures'

map global local-refresh r ': repl refresh changed<ret>' -docstring 'changed namespaces'
map global local-refresh a ': repl refresh all<ret>' -docstring 'all namespaces'
map global local-refresh c ': repl refresh clear<ret>' -docstring 'clear the refresh tracker'

# Modeline: show the REPL connection before the usual fields.
set-option global modelinefmt "%%opt{repl_modeline} %opt{modelinefmt}"
