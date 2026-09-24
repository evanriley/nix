function ta --description 'Create or attach a tmux session (default: dev)'
    if test (count $argv) -gt 1
        echo 'usage: ta [SESSION]' >&2
        return 2
    end
    set -l session dev
    if test (count $argv) -eq 1
        set session $argv[1]
    end
    if set -q TMUX
        tmux switch-client -t "=$session"
    else
        tmux new-session -A -s "$session"
    end
end
