# Language servers come from the project's shell (PATH). Each language also gets
# simple-completion-language-server, which serves snippets: friendly-snippets (pinned by
# flake.nix) plus your own in snippets/<language>.toml.

evaluate-commands %sh{
    command -v kak-lsp >/dev/null && kak-lsp ||
        echo "echo -debug 'kak-lsp is not on PATH; language servers are off'"
}

declare-option -docstring 'lsp_servers entry that serves snippets to every language' \
    str lsp_snippet_server %sh{
        cat <<EOF
[snippets]
command = "env"
args = ["SNIPPETS_PATH=$kak_config/snippets", "EXTERNAL_SNIPPETS_CONFIG=$kak_runtime/scls/external-snippets.toml", "simple-completion-language-server"]
root_globs = [".git", ".hg"]
EOF
    }

hook -group lsp-filetype-clojure global BufSetOption filetype=clojure %{
    set-option buffer lsp_servers %{
        [clojure-lsp]
        root_globs = ["deps.edn", "bb.edn", "project.clj", "shadow-cljs.edn", ".git"]
        settings_section = "_"
        [clojure-lsp.settings._]
    }
}

hook -group lsp-filetype-zig global BufSetOption filetype=zig %{
    set-option buffer lsp_servers %{
        [zls]
        root_globs = ["build.zig", "build.zig.zon", ".git"]
        settings_section = "zls"
        [zls.settings.zls]
        enable_build_on_save = true
    }
}

hook -group lsp-filetype-gleam global BufSetOption filetype=gleam %{
    set-option buffer lsp_servers %{
        [gleam]
        args = ["lsp"]
        root_globs = ["gleam.toml"]
    }
}

hook -group lsp-filetype-python global BufSetOption filetype=python %{
    set-option buffer lsp_servers %{
        [ruff]
        args = ["server", "--quiet"]
        root_globs = ["pyproject.toml", "uv.lock", "setup.py", ".git"]
        settings_section = "_"
        [ruff.settings._.globalSettings]
        organizeImports = true
        fixAll = true
    }
    # A type checker, when the project provides one.
    evaluate-commands %sh{
        for server in basedpyright-langserver pyright-langserver; do
            command -v "$server" >/dev/null || continue
            printf 'set-option -add buffer lsp_servers %%{\n[%s]\nargs = ["--stdio"]\nroot_globs = ["pyproject.toml", "uv.lock", "pyrightconfig.json", ".git"]\n}\n' "$server"
            break
        done
    }
}

# Rust keeps kak-lsp's own rust-analyzer defaults.

hook global BufSetOption filetype=(clojure|zig|gleam|python|rust|ocaml) %{
    set-option -add buffer lsp_servers "%opt{lsp_snippet_server}"
}

set-option global lsp_hover_anchor true
set-option global lsp_auto_show_code_actions true
set-option global lsp_inlay_diagnostic_sign '●'

try %{
    lsp-enable
    lsp-inlay-diagnostics-enable global
}

# Formatting: a buffer's formatcmd (Zig, Gleam) if it has one, the language server otherwise.
declare-option -docstring 'filetypes formatted on write' \
    str format_on_save_filetypes 'clojure|zig|gleam|python|rust|ocaml'
declare-option -docstring 'format on write in this buffer (toggle with <space>vf)' \
    bool format_on_save true

define-command code-format -docstring 'format the buffer' %{
    evaluate-commands %sh{
        if [ -n "$kak_opt_formatcmd" ]; then echo format-buffer; else echo lsp-formatting-sync; fi
    }
}

hook global WinSetOption "filetype=(%opt{format_on_save_filetypes})" %{
    hook window -group format-on-save BufWritePre .* %{
        evaluate-commands %sh{ [ "$kak_opt_format_on_save" = true ] && echo 'try code-format' }
    }
    hook -once -always window WinSetOption filetype=.* %{ remove-hooks window format-on-save }
}

define-command toggle-format-on-save -docstring 'toggle formatting on write for this buffer' %{
    evaluate-commands %sh{
        [ "$kak_opt_format_on_save" = true ] && v=false || v=true
        printf 'set-option buffer format_on_save %s\necho format on save: %s\n' "$v" "$v"
    }
}

declare-option -hidden bool show_inlay_diagnostics true
define-command toggle-inlay-diagnostics -docstring 'toggle diagnostics at the end of lines' %{
    evaluate-commands %sh{
        if [ "$kak_opt_show_inlay_diagnostics" = true ]; then
            printf 'lsp-inlay-diagnostics-disable global\nset-option global show_inlay_diagnostics false\n'
        else
            printf 'lsp-inlay-diagnostics-enable global\nset-option global show_inlay_diagnostics true\n'
        fi
    }
}

declare-option -hidden bool show_inlay_hints false
define-command toggle-inlay-hints -docstring 'toggle type hints' %{
    evaluate-commands %sh{
        if [ "$kak_opt_show_inlay_hints" = true ]; then
            printf 'lsp-inlay-hints-disable global\nset-option global show_inlay_hints false\n'
        else
            printf 'lsp-inlay-hints-enable global\nset-option global show_inlay_hints true\n'
        fi
    }
}
