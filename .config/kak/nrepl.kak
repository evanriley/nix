# Clojure through nREPL (the client is nrepl.py). Results show inline at the end of the
# evaluated form, in the echo area, and in a popup when they are long; everything,
# including printed output, goes to the log (, l …).

declare-option -docstring 'evaluate in this namespace instead of the buffer''s ns form' str nrepl_namespace
declare-option -docstring 'command that starts the project nREPL (default: detected; see nrepl.py)' \
    str-list nrepl_jack_in_command
declare-option -docstring 'show evaluation results inline' bool show_eval_results true
declare-option -docstring 'most runtime completion candidates offered at once' int nrepl_completion_limit 40

declare-option -hidden bool nrepl_connected false
declare-option -hidden int nrepl_port
declare-option -hidden str nrepl_report 'nrepl: nothing evaluated yet'
declare-option -hidden str nrepl_log_path
declare-option -hidden str nrepl_log_relay
declare-option -hidden str nrepl_cursor
declare-option -hidden str nrepl_saved_descs
declare-option -hidden str-list nrepl_saved_text
declare-option -hidden str nrepl_pending
declare-option -hidden str nrepl_buffer_namespace
declare-option -hidden range-specs nrepl_eval_results
declare-option -hidden int nrepl_eval_timestamp -1
declare-option -hidden int nrepl_eval_elapsed
declare-option -hidden completions nrepl_completions

set-face global InlayEvalResult comment
set-face global InlayEvalError Error

hook global GlobalSetOption nrepl_connected=true %{
    set-option global repl_modeline "nrepl:%opt{nrepl_port}"
}
hook global GlobalSetOption nrepl_connected=false %{ set-option global repl_modeline '' }

# One process per action: the helper sees the whole buffer (drafted with %), the cursor
# and the selections saved beforehand, and returns the commands to run afterwards.
define-command -hidden nrepl-run -params 1..2 %{
    set-option window nrepl_cursor "%val{cursor_line} %val{cursor_column}"
    set-option window nrepl_saved_descs %val{selections_desc}
    set-option window nrepl_saved_text %val{selections}
    set-option window nrepl_pending ''
    evaluate-commands -draft %{
        execute-keys '%'
        set-option window nrepl_pending %sh{
            # Kakoune exports only the variables a script mentions:
            # $kak_session $kak_client $kak_buffile $kak_bufname $kak_timestamp $kak_selection
            # $kak_opt_nrepl_cursor $kak_opt_nrepl_saved_descs $kak_quoted_opt_nrepl_saved_text
            # $kak_opt_nrepl_namespace $kak_quoted_opt_nrepl_jack_in_command
            if output=$(python3 "$kak_opt_config_dir/nrepl.py" "$@" 2>&1); then
                printf '%s' "$output"
            else
                printf "fail 'nrepl: %s'" "$(printf '%s' "$output" | tail -n 1 | sed "s/'/''/g")"
            fi
        }
    }
    evaluate-commands -save-regs c %opt{nrepl_pending}
}

define-command nrepl-eval -params 1 -docstring 'nrepl-eval <form|root|word|buffer|file|selection>' %{
    nrepl-run eval %arg{1}
}
define-command nrepl-eval-replace -docstring 'replace the form around the cursor with its value' %{
    nrepl-run replace
}
define-command nrepl-eval-comment -params 1 -docstring 'nrepl-eval-comment <form|root|word>: append the value as a comment' %{
    nrepl-run comment %arg{1}
}
define-command nrepl-interrupt -docstring 'interrupt the running evaluation' %{ nrepl-run interrupt }
define-command nrepl-jack-in -docstring 'connect to the project nREPL, starting one if needed' %{ nrepl-run jack-in }
define-command nrepl-connect -docstring 'connect to the nREPL named by .nrepl-port' %{ nrepl-run connect }
define-command nrepl-disconnect -docstring 'disconnect, leaving the server running' %{ nrepl-run disconnect }
define-command nrepl-quit -docstring 'disconnect and stop the REPL started by jack-in' %{ nrepl-run quit }
define-command nrepl-status -docstring 'show the connection' %{ nrepl-run status }
define-command nrepl-test -params 1 -docstring 'nrepl-test <cursor|namespace|all|rerun>: save, reload and test' %{
    project-update-root
    project-save
    nrepl-run test %arg{1}
}
define-command nrepl-refresh -params 1 -docstring 'nrepl-refresh <changed|all|clear>' %{ nrepl-run refresh %arg{1} }
define-command nrepl-doc -docstring 'documentation from the running REPL' %{ nrepl-run doc }
define-command nrepl-definition -docstring 'definition, as the running REPL knows it' %{ nrepl-run definition }
define-command nrepl-set-namespace -docstring 'evaluate in another namespace (empty: the ns form)' %{
    prompt -init %opt{nrepl_namespace} 'namespace: ' %{ set-option buffer nrepl_namespace %val{text} }
}

# Inline results -------------------------------------------------------------------------------

define-command -hidden nrepl-nop-with-0 nop

define-command -hidden nrepl-clear-results %{
    set-option buffer nrepl_eval_results %val{timestamp}
    set-option buffer nrepl_eval_timestamp %val{timestamp}
}

define-command -hidden nrepl-clear-results-if-edited %{
    set-option buffer nrepl_eval_elapsed %val{timestamp}
    set-option -remove buffer nrepl_eval_elapsed %opt{nrepl_eval_timestamp}
    try %{ evaluate-commands "nrepl-nop-with-%opt{nrepl_eval_elapsed}" } catch %{ nrepl-clear-results }
}

define-command -hidden nrepl-arm-results nrepl-clear-results

# nrepl-inline <buffer> <line> <timestamp at evaluation> <markup>: show a result after the
# last character of <line>, unless the buffer changed since the evaluation was sent.
define-command -hidden -params 4 nrepl-inline %{
    try %{
        evaluate-commands -buffer %arg{1} %{
            set-option buffer nrepl_eval_elapsed %val{timestamp}
            set-option -remove buffer nrepl_eval_elapsed %arg{3}
            evaluate-commands "nrepl-nop-with-%opt{nrepl_eval_elapsed}"
            evaluate-commands -draft %{
                execute-keys "%arg{2}g" gl l
                set-option -add buffer nrepl_eval_results "%val{cursor_line}.%val{cursor_column}+0|%arg{4}"
            }
        }
    }
}

define-command toggle-eval-results -docstring 'toggle inline evaluation results' %{
    evaluate-commands %sh{
        if [ "$kak_opt_show_eval_results" = true ]; then
            printf 'set-option global show_eval_results false\nremove-highlighter global/nrepl-eval-results\n'
        else
            printf 'set-option global show_eval_results true\nadd-highlighter global/nrepl-eval-results replace-ranges nrepl_eval_results\n'
        fi
    }
}

add-highlighter global/nrepl-eval-results replace-ranges nrepl_eval_results

hook global BufSetOption filetype=clojure %{
    remove-hooks buffer nrepl-eval-results
    hook buffer -group nrepl-eval-results NormalIdle .* nrepl-clear-results-if-edited
    hook buffer -group nrepl-eval-results InsertIdle .* nrepl-clear-results-if-edited
    hook buffer -group nrepl-eval-results BufReload .* nrepl-clear-results
}

# Runtime completion ------------------------------------------------------------------------

define-command -hidden nrepl-detect-namespace %{
    set-option buffer nrepl_buffer_namespace user
    try %{
        evaluate-commands -draft %{
            execute-keys '%s^\h*\(ns\s+(?:\^\S+\s+)*([^\s()\[\]{}]+)<ret>'
            set-option buffer nrepl_buffer_namespace %reg{1}
        }
    }
}

define-command -hidden nrepl-complete %{
    evaluate-commands %sh{ [ "$kak_opt_nrepl_connected" = true ] || echo fail }
    evaluate-commands -draft %{
        set-option window nrepl_cursor "%val{cursor_line} %val{cursor_column}"
        execute-keys x
        nop %sh{
            ns=${kak_opt_nrepl_namespace:-$kak_opt_nrepl_buffer_namespace}
            (python3 "$kak_opt_config_dir/nrepl.py" complete "$kak_buffile" "$kak_session" \
                "$kak_bufname" "$ns" $kak_opt_nrepl_cursor "$kak_timestamp" "$kak_selection" \
                "$kak_opt_nrepl_completion_limit" </dev/null >/dev/null 2>&1 &) >/dev/null 2>&1
        }
    }
}

hook global WinSetOption filetype=clojure %{
    nrepl-detect-namespace
    set-option -add window completers option=nrepl_completions
    hook window -group nrepl-completion InsertIdle .* %{ try nrepl-complete }
    hook window -group nrepl-completion BufWritePost .* nrepl-detect-namespace
    hook -once -always window WinSetOption filetype=.* %{
        remove-hooks window nrepl-completion
        set-option -remove window completers option=nrepl_completions
    }
}

# Log --------------------------------------------------------------------------------------

# Show the log in this client: a fifo buffer fed by tail -F, highlighted as Clojure.
define-command nrepl-log-show -docstring 'show the nREPL log in this client' %{
    nrepl-run log-path
    try %{ buffer *nrepl-log* } catch %{
        evaluate-commands %sh{
            log=$kak_opt_nrepl_log_path
            [ -n "$log" ] || { echo "fail 'nrepl: no log yet'"; exit; }
            touch "$log"
            fifo=$(mktemp -u "${TMPDIR:-/tmp}/kak-nrepl-log.XXXXXX")
            mkfifo -m 600 "$fifo"
            ( tail -F -n +1 "$log" > "$fifo" 2>/dev/null & echo $! > "$fifo.pid" ) </dev/null >/dev/null 2>&1
            printf "edit -fifo '%s' -scroll *nrepl-log*\n" "$fifo"
            printf "set-option global nrepl_log_relay '%s'\n" "$fifo"
        }
        try %{
            require-module clojure
            add-highlighter buffer/nrepl-log ref clojure
        }
        hook -once buffer BufClose .* nrepl-log-stop
    }
}

define-command -hidden nrepl-log-stop %{
    nop %sh{
        fifo=$kak_opt_nrepl_log_relay
        [ -n "$fifo" ] || exit 0
        [ -r "$fifo.pid" ] && kill "$(cat "$fifo.pid")" 2>/dev/null
        rm -f "$fifo" "$fifo.pid"
    }
    set-option global nrepl_log_relay ''
}
hook global KakEnd .* nrepl-log-stop

define-command -hidden nrepl-log -params 1 %{
    evaluate-commands %sh{
        case $1 in
            here) echo nrepl-log-show;;
            below|right|window)
                echo "try %{ evaluate-commands -client nrepl-log nop } catch %{ tmux-client $1 %{ rename-client nrepl-log; nrepl-log-show } }";;
            close)
                echo "try %{ evaluate-commands -client nrepl-log quit }"
                echo "try %{ delete-buffer *nrepl-log* }";;
            reset)
                echo "nrepl-run log-path"
                echo 'nop %sh{ [ -n "$kak_opt_nrepl_log_path" ] && : > "$kak_opt_nrepl_log_path" }'
                echo "try %{ delete-buffer *nrepl-log* }"
                echo "try %{ evaluate-commands -client nrepl-log nrepl-log-show }"
                echo "echo 'nrepl: log cleared'";;
        esac
    }
}
