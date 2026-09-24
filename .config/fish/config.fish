if not status is-interactive
    return
end

set -gx SHELL /usr/bin/fish
set -gx XDG_CONFIG_HOME $HOME/.config
set -gx ZVM_INSTALL $HOME/.zvm/self
set -gx EDITOR kak
set -gx VISUAL kak

fish_vi_key_bindings insert
set -g fish_cursor_default block
set -g fish_cursor_insert line
set -g fish_cursor_replace_one underscore
set -g fish_cursor_replace underscore
set -g fish_cursor_visual block

for tool_dir in $HOME/.local/bin $HOME/.cargo/bin $HOME/.zvm/bin $HOME/.zvm/self $HOME/.npm-global/bin
    if test -d $tool_dir
        fish_add_path --global --append $tool_dir
    end
end
if test -r ~/.local/state/darkman/fzf.fish
    source ~/.local/state/darkman/fzf.fish
end

set -g fish_greeting

alias vim=nvim

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -c'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

alias clj-repl='clj "-J-Dclojure.server.repl={:port 5555 :accept clojure.core.server/repl :server-daemon false}"'
alias nrepl "clojure -Sdeps '{:deps {nrepl/nrepl {:mvn/version \"1.7.0\"}}}' -M -m nrepl.cmdline --interactive"

function mkcd --description 'Create a directory and enter it'
    if test (count $argv) -ne 1
        echo 'usage: mkcd DIRECTORY' >&2
        return 2
    end

    mkdir -p -- $argv[1]; and cd -- $argv[1]
end

function serve --description 'Serve the current directory over HTTP'
    set -l port 8000
    if test (count $argv) -gt 0
        set port $argv[1]
    end

    python3 -m http.server $port
end

if command -q fzf
    fzf --fish | source
end

if command -q zoxide
    zoxide init fish | source
end

if command -q mise
    mise activate fish | source
end

if command -q opam
    opam env --shell=fish 2>/dev/null | source
end

if command -q direnv
    direnv hook fish | source
end
