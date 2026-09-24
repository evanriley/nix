# Windows are tmux panes. Outside tmux these fall back to Kakoune's own `terminal`.
# Every tmux call targets the pane of the client that asked, not the pane the server
# started in, so several clients of one session each get their own splits.

declare-option -docstring 'shell spawned by the terminal toggle' \
    str terminal_shell %sh{ printf %s "${SHELL:-/bin/sh}" }
declare-option -docstring 'height of panes opened below the editor, as tmux understands it' \
    str tmux_pane_height '30%'
declare-option -docstring 'width of panes opened beside the editor' \
    str tmux_pane_width '45%'
declare-option -hidden str tmux_terminal_pane

define-command -hidden tmux-required %{
    evaluate-commands %sh{
        [ -n "$TMUX" ] || printf "fail 'this needs Kakoune running inside tmux'\n"
    }
}

define-command tmux-split -params 2.. \
    -docstring 'tmux-split <below|right|window> <program> [<arguments>]: run a program in a new pane in the project root' %{
    project-update-root
    evaluate-commands %sh{
        placement=$1; shift
        root=${kak_opt_project_root:-$PWD}
        pane=${kak_client_env_TMUX_PANE}
        if [ -z "$TMUX" ]; then
            kq() { printf "'%s' " "$(printf %s "$1" | sed "s/'/''/g")"; }
            printf 'terminal sh -c '; kq 'cd "$1" && shift && exec "$@"'; kq _; kq "$root"
            for argument; do kq "$argument"; done
            echo
            exit
        fi
        case $placement in
            below) set -- split-window -v -l "$kak_opt_tmux_pane_height" ${pane:+-t "$pane"} -c "$root" -- "$@";;
            right) set -- split-window -h -l "$kak_opt_tmux_pane_width" ${pane:+-t "$pane"} -c "$root" -- "$@";;
            *) set -- new-window -c "$root" -- "$@";;
        esac
        tmux "$@" >/dev/null 2>&1 </dev/null
    }
}

define-command tmux-client -params 2 \
    -docstring 'tmux-client <below|right|window> <commands>: open another client of this session in a new pane, keeping focus here' %{
    evaluate-commands %sh{
        if [ -z "$TMUX" ]; then
            printf "new '%s'\n" "$(printf %s "$2" | sed "s/'/''/g")"
            exit
        fi
        pane=${kak_client_env_TMUX_PANE}
        commands=$2
        case $1 in
            below) set -- split-window -v -d -l "$kak_opt_tmux_pane_height" ${pane:+-t "$pane"};;
            right) set -- split-window -h -d -l "$kak_opt_tmux_pane_width" ${pane:+-t "$pane"};;
            *) set -- new-window -d;;
        esac
        tmux "$@" -- kak -c "$kak_session" -e "$commands" >/dev/null 2>&1 </dev/null
    }
}

define-command tmux-popup -params 1.. \
    -docstring 'tmux-popup <program> [<arguments>]: run a program in a popup over the editor' %{
    tmux-required
    project-update-root
    evaluate-commands %sh{
        "$kak_opt_config_dir/bin/kak-tmux-popup" "$kak_client_env_TMUX_PANE" \
            "${kak_opt_project_root:-$PWD}" 90% 90% "$@" ||
            echo "fail 'no tmux client to show a popup on'"
    }
}

define-command terminal-toggle -docstring 'show or hide a shell pane below the editor' %{
    evaluate-commands %sh{
        if [ -z "$TMUX" ]; then
            printf 'terminal %s\n' "$kak_opt_terminal_shell"
            exit
        fi
        here=${kak_client_env_TMUX_PANE}
        shell=$kak_opt_tmux_terminal_pane
        window=$(tmux display-message ${here:+-t "$here"} -p '#{window_id}')
        if [ -n "$shell" ] && tmux display-message -t "$shell" -p '' >/dev/null 2>&1; then
            if [ "$(tmux display-message -t "$shell" -p '#{window_id}')" = "$window" ]; then
                tmux break-pane -d -s "$shell" -n terminal
            else
                tmux join-pane -v -l "$kak_opt_tmux_pane_height" -s "$shell" ${here:+-t "$here"}
            fi
        else
            shell=$(tmux split-window -v -l "$kak_opt_tmux_pane_height" ${here:+-t "$here"} \
                -P -F '#{pane_id}' -c "$PWD" -- "$kak_opt_terminal_shell")
            printf "set-option global tmux_terminal_pane '%s'\n" "$shell"
        fi
    }
}
