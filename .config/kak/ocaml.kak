# OCaml: dune projects, opam files, ocamllsp and utop. Tools run through `opam exec` when
# opam is installed, so the active switch applies.

hook global BufCreate (.*/)?(dune|dune-project|dune-workspace)$ %{
    set-option buffer filetype lisp
}
hook global BufCreate (.*/)?([^/]+\.opam|opam)$ %{
    set-option buffer filetype opam
}

hook global BufSetOption filetype=opam %{
    set-option buffer comment_line '#'
    set-option buffer comment_block_begin '(*'
    set-option buffer comment_block_end '*)'
}
hook global WinSetOption filetype=opam %{
    add-highlighter window/opam regions
    add-highlighter window/opam/code default-region group
    add-highlighter window/opam/string region '"' '(?<!\\)(\\\\)*"' fill string
    add-highlighter window/opam/comment region '#' '$' fill comment
    add-highlighter window/opam/block-comment region -recurse \Q(* \Q(* \Q*) fill comment
    add-highlighter window/opam/code/field regex '^\h*[a-zA-Z][a-zA-Z0-9_-]*:' 0:keyword
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/opam }
}

hook global BufSetOption filetype=ocaml %{
    set-option buffer comment_line ''
    set-option buffer comment_block_begin '(*'
    set-option buffer comment_block_end '*)'
}

# dune verbs for OCaml sources and dune files.
hook global BufSetOption filetype=(ocaml|opam|lisp) %{
    evaluate-commands %sh{
        if [ "$kak_opt_filetype" = lisp ]; then
            case "${kak_buffile##*/}" in dune|dune-project|dune-workspace) ;; *) exit 0;; esac
        fi
        prefix=''
        command -v opam >/dev/null 2>&1 && prefix='opam exec --'
        printf '%s\n' \
            "set-option buffer build_command $prefix dune build" \
            "set-option buffer test_command $prefix dune runtest" \
            "set-option buffer watch_command $prefix dune build --watch" \
            "set-option buffer repl_command $prefix dune utop" \
            "set-option buffer repl_terminator ';;'"
    }
}

hook -group lsp-filetype-ocaml global BufSetOption filetype=ocaml %{
    evaluate-commands %sh{
        if command -v opam >/dev/null 2>&1; then
            spawn='command = "opam"
args = ["exec", "--", "ocamllsp"]'
        else
            spawn='command = "ocamllsp"'
        fi
        printf 'set-option buffer lsp_servers %%{\n[ocamllsp]\n%s\nroot_globs = ["dune-workspace", "dune-project", "*.opam", ".git"]\n}\n' "$spawn"
    }
}
