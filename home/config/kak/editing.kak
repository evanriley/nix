hook -group clipboard global RegisterModified '"' %{
    nop %sh{
        eval "set -- $kak_quoted_reg_dquote"
        # wl-copy must not inherit Kakoune's capture pipe or yanking can hang.
        exec >/dev/null 2>&1
        { separator=''; for selection; do
            printf '%s%s' "$separator" "$selection"
            separator='
'
        done; } | wl-copy --type text/plain
    }
}

define-command -hidden clipboard-paste -params 1 %{
    evaluate-commands -save-regs c %{
        set-register c %sh{ wl-paste --no-newline --type text/plain 2>/dev/null }
        execute-keys '"c' %arg{1}
    }
}

define-command trim-whitespace -docstring 'remove trailing whitespace from every line' %{
    try %{ execute-keys -draft '%s\h+$<ret>"_d' }
}

declare-option -hidden str move_line_ranges
declare-option -hidden int move_line_count
define-command -hidden move-lines -params 1 %{
    evaluate-commands -save-regs '/|"' %{
        set-option buffer move_line_ranges "%val{selections_desc}"
        set-option buffer move_line_count %val{buf_line_count}
        evaluate-commands -draft %{
            execute-keys '%'
            execute-keys '|python3 "$kak_opt_config_dir/support.py" move ' %arg{1} ' "$kak_opt_move_line_ranges" "$kak_opt_move_line_count" text<ret>'
        }
        evaluate-commands %sh{
            python3 "$kak_opt_config_dir/support.py" move "$1" "$kak_opt_move_line_ranges" "$kak_opt_move_line_count" select
        }
    }
}

try %{ enable-auto-pairs }

declare-user-mode surround
map global surround s ': surround<ret>' -docstring 'surround selection'
map global surround c ': change-surround<ret>' -docstring 'change surrounding pair'
map global surround d ': delete-surround<ret>' -docstring 'delete surrounding pair'
map global surround a ': select-surround<ret>' -docstring 'select surrounding pair'
map global surround t ': surround-with-tag<ret>' -docstring 'surround with tag'
map global surround T ': change-surrounding-tag<ret>' -docstring 'change surrounding tag'
map global surround D ': delete-surrounding-tag<ret>' -docstring 'delete surrounding tag'

# Lisps: parinfer owns the parentheses, so auto-pairs steps aside.

declare-option -hidden str parinfer_saved_auto_close

define-command parinfer-on -docstring 'enable parinfer (smart mode) in this window' %{
    evaluate-commands %sh{
        command -v parinfer-rust >/dev/null && exit 0
        printf "fail 'parinfer-rust is not on PATH; run the kak from modules/programs/kakoune.nix'\n"
    }
    set-option window parinfer_saved_auto_close %opt{auto_close_trigger}
    set-option window auto_close_trigger '<a-k>(?!)<ret>'
    parinfer-enable-window -smart
}

define-command parinfer-off -docstring 'disable parinfer in this window' %{
    try %{ parinfer-disable-window }
    try %{ unset-option window auto_close_trigger }
}

define-command parinfer-toggle -docstring 'toggle parinfer in this window' %{
    evaluate-commands %sh{
        if [ "$kak_opt_parinfer_enabled" = true ]; then echo parinfer-off; else echo parinfer-on; fi
    }
}

hook global WinSetOption filetype=(clojure|lisp|scheme|janet|fennel) %{
    try parinfer-on
    try rainbow-enable-window
    hook -once -always window WinSetOption filetype=.* %{
        parinfer-off
        try rainbow-disable-window
    }
}

try %{ set-option global rainbow_colors MatchingChar type string function keyword module }
