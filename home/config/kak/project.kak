# Commands are str-lists; test_file_command and test_cursor_command may use {file} and
# {name} (the test around the cursor, found with test_name_regex). A project can override
# any of them in a .kakrc at its root (<space>cC loads it).

declare-option -docstring 'files that mark a project root, nearest first' \
    str-list project_root_files 'build.zig' 'gleam.toml' 'Cargo.toml' 'pyproject.toml' \
    'deps.edn' 'bb.edn' 'project.clj' 'shadow-cljs.edn' 'dune-project' '.git' '.hg'
declare-option -docstring 'root of the project the current buffer belongs to' str project_root

declare-option str-list build_command
declare-option str-list test_command
declare-option str-list run_command
declare-option str-list watch_command
declare-option -docstring 'command for the REPL pane of languages without nREPL' str-list repl_command
declare-option -docstring 'test one file; {file} is replaced' str-list test_file_command
declare-option -docstring 'test the test at the cursor; {file} and {name} are replaced' str-list test_cursor_command
declare-option -docstring 'regex whose first group names the test around the cursor' str test_name_regex

define-command project-update-root -docstring 'recompute project_root for this buffer' %{
    set-option window project_root %sh{
        : "$kak_buffile"
        python3 "$kak_opt_config_dir/support.py" root "$kak_quoted_opt_project_root_files"
    }
}

hook global BufSetOption filetype=zig %<
    set-option buffer tabstop 4
    set-option buffer indentwidth 4
    set-option buffer formatcmd 'zig fmt --stdin'
    set-option buffer build_command zig build
    set-option buffer test_command zig build test
    set-option buffer run_command zig build run
    set-option buffer watch_command zig build --watch
    set-option buffer test_file_command zig test '{file}'
    set-option buffer test_cursor_command zig test '{file}' --test-filter '{name}'
    set-option buffer test_name_regex '^\h*test\h+"?([^"{]*?)"?\h*\{'
>

hook global BufSetOption filetype=gleam %{
    set-option buffer formatcmd 'gleam format --stdin'
    set-option buffer build_command gleam build
    set-option buffer test_command gleam test
    set-option buffer run_command gleam run
    set-option buffer test_file_command gleam test
    set-option buffer test_cursor_command gleam test
}

hook global BufSetOption filetype=rust %{
    set-option buffer tabstop 4
    set-option buffer indentwidth 4
    set-option buffer build_command cargo build
    set-option buffer test_command cargo test
    set-option buffer run_command cargo run
    set-option buffer watch_command bacon
    set-option buffer test_file_command cargo test
    set-option buffer test_cursor_command cargo test '{name}'
    set-option buffer test_name_regex '^\h*(?:pub(?:\([^)]*\))?\h+)?(?:async\h+)?fn\h+(\w+)'
}

hook global BufSetOption filetype=python %{
    set-option buffer tabstop 4
    set-option buffer indentwidth 4
    evaluate-commands %sh{
        dir=$(dirname -- "${kak_buffile:-$PWD/x}")
        runner=''
        while [ "$dir" != / ]; do
            if [ -e "$dir/uv.lock" ]; then runner='uv run'; break; fi
            [ -e "$dir/pyproject.toml" ] && break
            dir=$(dirname -- "$dir")
        done
        printf 'set-option buffer run_command %s python {file}\n' "$runner"
        printf 'set-option buffer test_command %s pytest\n' "$runner"
        printf "set-option buffer test_file_command %s pytest '{file}'\n" "$runner"
        printf "set-option buffer test_cursor_command %s pytest '{file}' -k '{name}'\n" "$runner"
        if [ -n "$runner" ]; then
            printf 'set-option buffer repl_command uv run python\n'
        elif command -v ipython >/dev/null; then
            printf 'set-option buffer repl_command ipython\n'
        else
            printf 'set-option buffer repl_command python3\n'
        fi
    }
    set-option buffer test_name_regex '^\h*(?:async\h+)?def\h+(test\w*)'
}

hook global BufSetOption filetype=clojure %{
    evaluate-commands %sh{
        dir=$(dirname -- "${kak_buffile:-$PWD/x}")
        while [ "$dir" != / ]; do
            [ -e "$dir/deps.edn" ] || [ -e "$dir/bb.edn" ] || [ -e "$dir/project.clj" ] && break
            dir=$(dirname -- "$dir")
        done
        if [ -e "$dir/bb.edn" ] && grep -Eq '^[[:space:]]*test[[:space:]]' "$dir/bb.edn"; then
            echo 'set-option buffer test_command bb test'
        elif [ -e "$dir/deps.edn" ] && grep -q ':test' "$dir/deps.edn"; then
            echo 'set-option buffer test_command clojure -M:test'
        elif [ -e "$dir/project.clj" ]; then
            echo 'set-option buffer test_command lein test'
        fi
        if [ -e "$dir/bb.edn" ] && grep -Eq '^[[:space:]]*build[[:space:]]' "$dir/bb.edn"; then
            echo 'set-option buffer build_command bb build'
        fi
    }
}

define-command -hidden project-save %{
    evaluate-commands -buffer * %{
        evaluate-commands %sh{
            [ "$kak_modified" = true ] && [ -n "$kak_buffile" ] || exit 0
            case "$kak_buffile" in "$kak_opt_project_root"/*) echo write;; esac
        }
    }
}

# project-run <make|pane> <verb> <command…>: save the project's buffers, fill in {file} and
# {name}, then run in the *make* buffer (errors are jumpable) or in a tmux pane.
define-command -hidden project-run -params 2.. %{
    project-update-root
    project-save
    evaluate-commands %sh{
        mode=$1 verb=$2
        shift 2
        if [ $# -eq 0 ]; then
            printf "fail 'no %s command for %s; set-option buffer %s_command …'\n" \
                "$verb" "${kak_opt_filetype:-this buffer}" "$verb"
            exit
        fi
        kq() { printf "'%s' " "$(printf %s "$1" | sed "s/'/''/g")"; }
        sq() { printf " '%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }
        replace() {
            text=$1 out=
            while :; do
                case $text in
                    *"$2"*) out=$out${text%%"$2"*}$3; text=${text#*"$2"};;
                    *) break;;
                esac
            done
            printf %s "$out$text"
        }
        for argument; do
            shift
            argument=$(replace "$argument" '{file}' "$kak_buffile")
            argument=$(replace "$argument" '{name}' "$kak_opt_test_name")
            set -- "$@" "$argument"
        done
        if [ "$mode" = make ]; then
            line="python3$(sq "$kak_opt_config_dir/support.py") build$(sq "$kak_opt_project_root")"
            for argument; do line="$line$(sq "$argument")"; done
            printf 'set-option local makecmd '; kq "$line"; printf '\nmake\n'
        else
            printf 'tmux-split below sh -c '
            kq "\"\$@\"; printf '\\n[exit %s] ' \"\$?\"; read -r _"
            kq _
            for argument; do kq "$argument"; done
            echo
        fi
    }
}

declare-option -hidden str test_name

define-command build -docstring 'build the project' %{ project-run make build %opt{build_command} }
define-command test -docstring 'run the project tests' %{ project-run make test %opt{test_command} }
define-command run -docstring 'run the project in a pane' %{ project-run pane run %opt{run_command} }
define-command watch -docstring 'run the watcher in a pane' %{ project-run pane watch %opt{watch_command} }
define-command test-file -docstring 'test the current file' %{
    project-run make test_file %opt{test_file_command}
}
define-command test-cursor -docstring 'run the test around the cursor' %{
    set-option window test_name ''
    try %{
        evaluate-commands -draft %{
            execute-keys gl "<a-/>%opt{test_name_regex}<ret>"
            set-option window test_name %reg{1}
        }
    }
    evaluate-commands %sh{
        case "${kak_quoted_opt_test_cursor_command}" in
            *'{name}'*) [ -n "$kak_opt_test_name" ] || printf "fail 'no test around the cursor'\n";;
        esac
    }
    project-run make test_cursor %opt{test_cursor_command}
}

define-command project-config -docstring 'source the project''s .kakrc' %{
    project-update-root
    source "%opt{project_root}/.kakrc"
}
