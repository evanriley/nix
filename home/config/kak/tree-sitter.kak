# Grammars, queries and the kak-tree-sitter config come from modules/programs/kakoune.nix.

evaluate-commands %sh{
    config="$kak_runtime/tree-sitter/config.toml"
    command -v kak-tree-sitter >/dev/null && [ -r "$config" ] || exit 0
    # One server serves every session. After a flake update it would keep the old grammars,
    # so replace a server that was started with another build's config.
    for pid in $(pgrep -x kak-tree-sitter); do
        tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -qxF -- "$config" && continue
        kill "$pid" 2>/dev/null
        while kill -0 "$pid" 2>/dev/null; do sleep 0.05; done
    done
    kak-tree-sitter --kakoune --daemonize --server --init "$kak_session" --config "$config"
}

# Monobiome (like most themes) only styles Kakoune's standard faces, so point the
# tree-sitter faces at them. Anything not listed falls back to its parent group.
try %{
    set-face global ts_attribute attribute
    set-face global ts_comment comment
    set-face global ts_constant value
    set-face global ts_constant_builtin builtin
    set-face global ts_constant_character_escape meta
    set-face global ts_constructor type
    set-face global ts_function function
    set-face global ts_function_builtin builtin
    set-face global ts_function_macro meta
    set-face global ts_keyword keyword
    set-face global ts_keyword_directive meta
    set-face global ts_label meta
    set-face global ts_namespace module
    set-face global ts_operator operator
    set-face global ts_punctuation delimiter
    set-face global ts_punctuation_bracket bracket
    set-face global ts_special meta
    set-face global ts_string string
    set-face global ts_string_regexp meta
    set-face global ts_string_special meta
    set-face global ts_string_special_symbol value
    set-face global ts_tag keyword
    set-face global ts_type type
    set-face global ts_type_builtin type
    set-face global ts_variable variable
    set-face global ts_variable_builtin builtin
    set-face global ts_variable_other_member variable
    set-face global ts_variable_parameter variable
    set-face global ts_markup_heading title
    set-face global ts_markup_raw mono
}
