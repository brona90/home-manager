#!/usr/bin/env bash
# pinentry-emacs-frame — Assuan pinentry that routes to the Emacs daemon
set -u
umask 077

SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs/server"
EMACSCLIENT="@emacsclient@"
PINENTRY_TTY_FALLBACK="@pinentry_tty@"

desc=""; prompt=""; errmsg=""; title=""; ok="OK"; cancel="Cancel"
notok=""; keyinfo=""; repeat=""; repeat_err=""

pct_decode() {
    local s=$1 out="" i=0 n=${#s} c
    while (( i < n )); do
        c=${s:i:1}
        if [[ $c == "%" && $((i+2)) -lt $n ]]; then
            printf -v out '%s\x%s' "$out" "${s:i+1:2}"
            i=$((i+3))
        else
            out+=$c; i=$((i+1))
        fi
    done
    printf '%b' "$out"
}
pct_encode() {
    local s=$1 out="" i c
    for (( i=0; i<${#s}; i++ )); do
        c=${s:i:1}
        case $c in
            $'\r') out+="%0D" ;;
            $'\n') out+="%0A" ;;
            '%')   out+="%25" ;;
            *)     out+=$c ;;
        esac
    done
    printf '%s' "$out"
}
elisp_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
}

emit() { printf '%s\r\n' "$*"; }

do_getpin() {
    local eD eP eE expr result
    eD=$(elisp_escape "$desc")
    eP=$(elisp_escape "${prompt:-Passphrase:}")
    eE=$(elisp_escape "$errmsg")
    expr="(my/pinentry-read-pin ${eD} ${eP} ${eE})"
    if ! result=$(timeout 120 "$EMACSCLIENT" --socket-name "$SOCK" --eval "$expr" 2>/dev/null); then
        emit "ERR 83886179 Operation cancelled <emacs>"
        return
    fi
    if [[ $result == '":cancel"' || $result == ":cancel" ]]; then
        emit "ERR 83886179 Operation cancelled <emacs>"
        return
    fi
    result=${result#\"}; result=${result%\"}
    result=${result//\\n/$'\n'}
    result=${result//\\\"/\"}
    result=${result//\\\\/\\}
    emit "D $(pct_encode "$result")"
    emit "OK"
    result=""
}

do_confirm() {
    local eD expr result
    eD=$(elisp_escape "${desc:-Confirm}")
    expr="(my/pinentry-yes-or-no-p ${eD})"
    if result=$(timeout 120 "$EMACSCLIENT" --socket-name "$SOCK" --eval "$expr" 2>/dev/null) && [[ $result == "t" ]]; then
        emit "OK"
    else
        emit "ERR 83886194 Not confirmed <emacs>"
    fi
}

# If daemon is absent, exec pinentry-tty so that plain-tty callers keep working.
if ! [[ -S "$SOCK" ]] || ! "$EMACSCLIENT" --socket-name "$SOCK" --eval 't' >/dev/null 2>&1; then
    exec "$PINENTRY_TTY_FALLBACK" "$@"
fi

emit "OK Pleased to meet you, process $$"
while IFS= read -r line; do
    line=${line%$'\r'}
    cmd=${line%% *}
    arg=""; [[ $line == *" "* ]] && arg=$(pct_decode "${line#* }")
    case $cmd in
        SETDESC)        desc=$arg;        emit "OK" ;;
        SETPROMPT)      prompt=$arg;      emit "OK" ;;
        SETERROR)       errmsg=$arg;      emit "OK" ;;
        SETTITLE)       title=$arg;       emit "OK" ;;
        SETOK)          ok=$arg;          emit "OK" ;;
        SETCANCEL)      cancel=$arg;      emit "OK" ;;
        SETNOTOK)       notok=$arg;       emit "OK" ;;
        SETKEYINFO)     keyinfo=$arg;     emit "OK" ;;
        SETREPEAT)      repeat=$arg;      emit "OK" ;;
        SETREPEATERROR) repeat_err=$arg;  emit "OK" ;;
        OPTION)         emit "OK" ;;
        NOP)            emit "OK" ;;
        RESET)          desc=""; prompt=""; errmsg=""; title=""; emit "OK" ;;
        GETINFO)
            case $arg in
                pid)            emit "D $$";                         emit "OK" ;;
                version)        emit "D 1.2.1";                      emit "OK" ;;
                flavor)         emit "D emacs-frame";                emit "OK" ;;
                pinentry-info)  emit "D pinentry-emacs-frame";       emit "OK" ;;
                *)              emit "OK" ;;
            esac ;;
        GETPIN)     do_getpin ;;
        CONFIRM)    do_confirm ;;
        MESSAGE)    do_confirm ;;
        BYE)        emit "OK closing connection"; exit 0 ;;
        "")         : ;;
        *)          emit "OK" ;;
    esac
done
