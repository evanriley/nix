# Pickers: fzf with a preview in a tmux popup, or Kakoune's own fuzzy prompt outside tmux.

declare-option -docstring 'most recently opened files remembered for the recent-files picker' \
    int recent_files_limit 200
declare-option -docstring 'file holding the recent-files list' \
    str recent_files_path %sh{ printf '%s/kak-mru' "${XDG_CACHE_HOME:-$HOME/.cache}" }

hook global WinDisplay .* %{
    nop %sh{
        [ -n "$kak_buffile" ] && [ -f "$kak_buffile" ] || exit 0
        python3 "$kak_opt_config_dir/support.py" recent \
            "$kak_opt_recent_files_path" "$kak_buffile" "$kak_opt_recent_files_limit"
    }
}

define-command -hidden picker -params 1..2 %{
    project-update-root
    evaluate-commands %sh{
        [ -n "$TMUX" ] || { printf 'picker-prompt-%s\n' "$1"; exit; }
        extra=$2
        [ "$1" = recent ] && extra=$kak_opt_recent_files_path
        "$kak_opt_config_dir/bin/kak-tmux-popup" "$kak_client_env_TMUX_PANE" \
            "$kak_opt_project_root" 90% 85% \
            "$kak_opt_config_dir/bin/kak-pick" "$1" "$kak_session" "$kak_client" \
            "$kak_opt_project_root" "$extra" || printf 'picker-prompt-%s\n' "$1"
    }
}

define-command picker-files -docstring 'find a project file' %{ picker files }
define-command picker-git -docstring 'find a file git knows about' %{ picker git }
define-command picker-recent -docstring 'find a recently opened file' %{ picker recent }
define-command picker-grep -docstring 'search the project as you type' %{ picker grep }
define-command picker-grep-word -docstring 'search the project for the selection' %{
    picker grep %val{selection}
}

define-command picker-buffers -docstring 'switch to an open buffer' %{
    prompt -menu -buffer-completion 'buffer: ' %{ buffer %val{text} }
}

# Fallbacks without tmux ---------------------------------------------------------------------

define-command -hidden picker-prompt-files %{
    prompt -menu -shell-script-candidates %{
        cd "$kak_opt_project_root" || exit
        fd --type f --hidden --exclude .git --follow --strip-cwd-prefix
    } 'file: ' %{ edit -existing "%opt{project_root}/%val{text}" }
}

define-command -hidden picker-prompt-git %{
    prompt -menu -shell-script-candidates %{
        cd "$kak_opt_project_root" || exit
        git ls-files --cached --others --exclude-standard 2>/dev/null
    } 'git file: ' %{ edit -existing "%opt{project_root}/%val{text}" }
}

define-command -hidden picker-prompt-recent %{
    prompt -menu -shell-script-candidates %{
        [ -r "$kak_opt_recent_files_path" ] || exit 0
        while IFS= read -r path; do [ -f "$path" ] && printf '%s\n' "$path"; done \
            < "$kak_opt_recent_files_path"
    } 'recent: ' %{ edit -existing %val{text} }
}

define-command -hidden picker-prompt-grep %{
    prompt -menu -shell-script-completion %{
        [ -n "$1" ] || exit 0
        cd "$kak_opt_project_root" || exit
        rg --line-number --column --no-heading --color=never --smart-case -- "$1" . 2>/dev/null | head -n 200
    } 'grep: ' %{
        evaluate-commands %sh{
            python3 "$kak_opt_config_dir/support.py" grep-open "$kak_opt_project_root" "$kak_text"
        }
    }
}
