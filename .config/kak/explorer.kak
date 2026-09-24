# A small oil.nvim: a directory as an editable buffer.
#   -        open the current file's directory, or go up from a directory buffer
#   <ret>    open the entry under the cursor
#   g.       show or hide dotfiles
#   :w       apply your edits: a changed line renames (add a / to move into a directory),
#            a deleted line deletes (to the trash), a new line creates (end it with / for a
#            directory). You confirm the summary first.

declare-option -hidden str explorer_dir
declare-option -hidden str-list explorer_entries
declare-option -hidden str explorer_plan
declare-option -hidden str explorer_pending
declare-option -docstring 'show dotfiles in the explorer' bool explorer_hidden false

define-command explorer -params ..1 -file-completion \
    -docstring 'explorer [<directory>]: browse a directory (default: the current file''s)' %{
    evaluate-commands %sh{
        dir=$1
        if [ -z "$dir" ]; then
            if [ -n "$kak_opt_explorer_dir" ]; then dir=$kak_opt_explorer_dir
            elif [ -n "$kak_buffile" ]; then dir=$(dirname -- "$kak_buffile")
            else dir=$PWD; fi
        fi
        case $dir in /*) ;; *) dir=$PWD/$dir;; esac
        dir=$(cd -- "$dir" 2>/dev/null && pwd -P) || { printf "fail 'no such directory'\n"; exit; }
        from=${kak_buffile##*/}
        printf "explorer-show '%s' '%s'\n" "$(printf %s "$dir" | sed "s/'/''/g")" \
            "$(printf %s "$from" | sed "s/'/''/g")"
    }
}

define-command -hidden explorer-show -params 2 %{
    try %{ delete-buffer! *explorer* }
    edit -scratch *explorer*
    set-option buffer explorer_dir %arg{1}
    set-option buffer filetype explorer
    explorer-fill
    try %{ execute-keys "/^\Q%arg{2}\E/?$<ret>;gh" } catch %{ execute-keys gg }
    echo -- %arg{1}
}

define-command -hidden explorer-fill %{
    evaluate-commands -save-regs '/"|' %{
        execute-keys '%|python3 "$kak_opt_config_dir/support.py" explorer-list "$kak_opt_explorer_dir" "$kak_opt_explorer_hidden"<ret>'
        set-option buffer explorer_entries
        try %{
            evaluate-commands -draft %{
                execute-keys '%s^[^\n]+<ret>'
                set-option buffer explorer_entries %val{selections}
            }
        }
    }
    execute-keys gg
}

define-command -hidden explorer-open %{
    evaluate-commands -save-regs e %{
        evaluate-commands -draft %{ execute-keys 'x_'; set-register e %val{selection} }
        evaluate-commands %sh{
            entry=$kak_reg_e
            q() { printf "'%s'" "$(printf %s "$1" | sed "s/'/''/g")"; }
            case $entry in
                */) printf 'explorer %s\n' "$(q "$kak_opt_explorer_dir/$entry")" ;;
                ''|*[[:space:]]) printf "fail 'no entry on this line'\n" ;;
                *) printf 'edit -existing %s\n' "$(q "$kak_opt_explorer_dir/$entry")" ;;
            esac
        }
    }
}

define-command -hidden explorer-up %{
    evaluate-commands %sh{
        parent=$(dirname -- "$kak_opt_explorer_dir")
        child=${kak_opt_explorer_dir##*/}
        printf "explorer-show '%s' '%s'\n" "$(printf %s "$parent" | sed "s/'/''/g")" \
            "$(printf %s "$child" | sed "s/'/''/g")"
    }
}

define-command -hidden explorer-toggle-hidden %{
    evaluate-commands %sh{
        [ "$kak_opt_explorer_hidden" = true ] && v=false || v=true
        printf 'set-option global explorer_hidden %s\n' "$v"
    }
    explorer-fill
}

define-command -hidden explorer-save %{
    evaluate-commands -draft %{
        execute-keys '%'
        set-option buffer explorer_pending %sh{
            python3 "$kak_opt_config_dir/support.py" explorer-plan \
                "$kak_opt_explorer_dir" "$kak_quoted_opt_explorer_entries" "$kak_selection"
        }
    }
    evaluate-commands %opt{explorer_pending}
}

define-command -hidden explorer-apply %{
    evaluate-commands %sh{
        python3 "$kak_opt_config_dir/support.py" explorer-apply "$kak_opt_explorer_plan"
    }
    explorer-fill
}

hook global BufSetOption filetype=explorer %{
    map buffer normal <ret> ': explorer-open<ret>'
    map buffer normal <minus> ': explorer-up<ret>'
    map buffer goto . '<esc>: explorer-toggle-hidden<ret>' -docstring 'toggle dotfiles'
    alias buffer w explorer-save
    alias buffer write explorer-save
    add-highlighter buffer/explorer regex '^[^\n]*/$' 0:function
}
