# The REPL layer behind the , (local leader) keys. Every language gets the same verbs;
# repl_backend says who answers them:
#   nrepl  Clojure, through nrepl.kak
#   tmux   languages with a repl_command (Python): text is pasted into a REPL pane
#   ''     no REPL: eval keys explain themselves, test keys use the project commands

declare-option -docstring 'who evaluates code for this buffer: nrepl, tmux or empty' str repl_backend
declare-option -docstring 'shown in the modeline while a REPL is connected' str repl_modeline

hook global BufSetOption filetype=clojure %{ set-option buffer repl_backend nrepl }
hook global BufSetOption repl_command=.+ %{
    evaluate-commands %sh{
        [ -n "$kak_opt_repl_command" ] && [ "$kak_opt_filetype" != clojure ] &&
            echo 'set-option buffer repl_backend tmux'
    }
}

define-command repl -params 1.. -docstring 'repl <action> [<arguments>]: run a REPL action with this buffer''s backend' %{
    evaluate-commands %sh{
        if [ -z "$kak_opt_repl_backend" ]; then
            printf "fail 'no REPL for %s buffers; build and test with <space>c'\n" "${kak_opt_filetype:-these}"
            exit
        fi
        case "$kak_opt_repl_backend:$1" in
            tmux:eval|tmux:interrupt|tmux:connect|tmux:jack-in|tmux:disconnect|tmux:quit|tmux:log|tmux:status|nrepl:*) ;;
            *) printf "fail 'the %s REPL cannot %s'\n" "$kak_opt_repl_backend" "$1"; exit;;
        esac
        printf '%s-%s' "$kak_opt_repl_backend" "$1"
        shift
        for argument; do printf " '%s'" "$(printf %s "$argument" | sed "s/'/''/g")"; done
        echo
    }
}

# Tests use the REPL when one is connected (Clojure), the project's test commands otherwise.
define-command repl-test -params 1 -docstring 'repl-test <cursor|namespace|all|rerun>' %{
    evaluate-commands %sh{
        if [ "$kak_opt_repl_backend" = nrepl ] && [ "$kak_opt_nrepl_connected" = true ]; then
            echo "nrepl-test $1"
            exit
        fi
        case $1 in
            cursor) echo test-cursor;;
            namespace) echo test-file;;
            all) echo test;;
            *) echo "fail 'rerunning failures needs a connected nREPL'";;
        esac
    }
}

# Documentation and definitions come from the running REPL when there is one.
define-command repl-doc -docstring 'documentation for the symbol under the cursor' %{
    evaluate-commands %sh{
        if [ "$kak_opt_repl_backend" = nrepl ] && [ "$kak_opt_nrepl_connected" = true ]; then
            echo nrepl-doc
        else
            echo lsp-hover
        fi
    }
}

define-command repl-definition -docstring 'go to the definition of the symbol under the cursor' %{
    evaluate-commands %sh{
        if [ "$kak_opt_repl_backend" = nrepl ] && [ "$kak_opt_nrepl_connected" = true ]; then
            echo 'try nrepl-definition catch lsp-definition'
        else
            echo lsp-definition
        fi
    }
}

# tmux backend -----------------------------------------------------------------------------

declare-option -hidden str tmux_repl_pane
declare-option -docstring 'appended to code sent to the REPL pane (OCaml: ;;)' str repl_terminator

define-command -hidden tmux-repl-alive %{
    evaluate-commands %sh{
        pane=$kak_opt_tmux_repl_pane
        [ -n "$TMUX" ] || { echo "fail 'the REPL pane needs Kakoune inside tmux'"; exit; }
        if [ -z "$pane" ] || ! tmux display-message -t "$pane" -p '' >/dev/null 2>&1; then
            echo "fail 'no REPL pane; start one with , c c'"
        fi
    }
}

define-command -hidden tmux-connect %{
    project-update-root
    evaluate-commands %sh{
        [ -n "$TMUX" ] || { echo "fail 'the REPL pane needs Kakoune inside tmux'"; exit; }
        pane=$kak_opt_tmux_repl_pane
        if [ -n "$pane" ] && tmux display-message -t "$pane" -p '' >/dev/null 2>&1; then
            echo "echo 'repl: already running in pane $pane'"
            exit
        fi
        eval "set -- $kak_quoted_opt_repl_command"
        here=${kak_client_env_TMUX_PANE}
        pane=$(tmux split-window -h -d -l "$kak_opt_tmux_pane_width" ${here:+-t "$here"} \
            -P -F '#{pane_id}' -c "$kak_opt_project_root" -- "$@")
        printf "set-option global tmux_repl_pane '%s'\n" "$pane"
        printf "set-option global repl_modeline 'repl:%s'\n" "$1"
        printf "echo 'repl: started %s'\n" "$*"
    }
}

define-command -hidden tmux-send -params 1 %{
    tmux-repl-alive
    nop %sh{
        printf '%s%s\n' "$1" "$kak_opt_repl_terminator" | tmux load-buffer -b kak-repl -
        tmux paste-buffer -p -d -b kak-repl -t "$kak_opt_tmux_repl_pane"
        tmux send-keys -t "$kak_opt_tmux_repl_pane" Enter
    }
}

define-command -hidden tmux-eval -params 1 %{
    evaluate-commands -draft %{
        evaluate-commands %sh{
            case $1 in
                form) echo "execute-keys x";;
                root) echo "execute-keys <a-a>p";;
                word) echo "execute-keys <a-i>w";;
                buffer|file) echo "execute-keys '%'";;
                selection) ;;
            esac
        }
        tmux-send %val{selection}
    }
}

define-command -hidden tmux-jack-in tmux-connect
define-command -hidden tmux-quit tmux-disconnect

define-command -hidden tmux-interrupt %{
    tmux-repl-alive
    nop %sh{ tmux send-keys -t "$kak_opt_tmux_repl_pane" C-c }
}

define-command -hidden tmux-disconnect %{
    nop %sh{ [ -n "$kak_opt_tmux_repl_pane" ] && tmux kill-pane -t "$kak_opt_tmux_repl_pane" 2>/dev/null }
    set-option global tmux_repl_pane ''
    set-option global repl_modeline ''
}

define-command -hidden tmux-log -params 1 %{
    tmux-repl-alive
    nop %sh{
        pane=$kak_opt_tmux_repl_pane
        here=${kak_client_env_TMUX_PANE}
        window=$(tmux display-message ${here:+-t "$here"} -p '#{window_id}')
        case $1 in
            close) tmux break-pane -d -s "$pane" -n repl ;;
            *)
                if [ "$(tmux display-message -t "$pane" -p '#{window_id}')" != "$window" ]; then
                    case $1 in
                        below) tmux join-pane -d -v -l "$kak_opt_tmux_pane_height" -s "$pane" ${here:+-t "$here"} ;;
                        *) tmux join-pane -d -h -l "$kak_opt_tmux_pane_width" -s "$pane" ${here:+-t "$here"} ;;
                    esac
                fi ;;
        esac
    }
}

define-command -hidden tmux-status %{
    tmux-repl-alive
    echo "repl: pane %opt{tmux_repl_pane}"
}
