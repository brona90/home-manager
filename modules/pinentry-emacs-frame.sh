#!/usr/bin/env bash
# pinentry-emacs-frame — Assuan pinentry dispatcher
#
# Routes passphrase prompts based on context:
#   - If the gpg client has a tty (OPTION ttyname=...), hand off to
#     pinentry-tty by replaying the accumulated protocol.  This gives
#     the user a native curses prompt on their terminal.
#   - Otherwise (Emacs Magit, no tty), prompt in the Emacs daemon's
#     minibuffer via emacsclient --eval.
set -u
umask 077

SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs/server"
EMACSCLIENT="@emacsclient@"
PINENTRY_TTY="@pinentry_tty@"

desc=""; prompt=""; errmsg=""
ttyname=""

# Accumulated protocol lines — replayed to pinentry-tty on handoff
declare -a protocol_buf=()

pct_decode() {
    local s="${1:-}" out="" i=0 c n
    n=${#s}
    while (( i < n )); do
        c=${s:i:1}
        if [[ $c == "%" && $((i+2)) -le $n ]]; then
            printf -v out '%s\x%s' "$out" "${s:i+1:2}"
            i=$((i+3))
        else
            out+=$c; i=$((i+1))
        fi
    done
    printf '%b' "$out"
}
pct_encode() {
    local s="${1:-}" out="" i c
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
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
}

emit() { printf '%s\r\n' "$*"; }

# ── Hand off to pinentry-tty ────────────────────────────────────────
# Replay accumulated protocol, then proxy the rest of the conversation.
handoff_to_pinentry_tty() {
    local current_cmd="$1"
    # Launch pinentry-tty as a coprocess
    coproc PTY { "$PINENTRY_TTY" "$@"; }

    # Read pinentry-tty's greeting, forward to agent
    local greeting
    IFS= read -r greeting <&"${PTY[0]}"
    printf '%s\r\n' "$greeting"

    # Replay buffered lines
    for buffered in "${protocol_buf[@]}"; do
        printf '%s\r\n' "$buffered" >&"${PTY[1]}"
        IFS= read -r reply <&"${PTY[0]}"
        printf '%s\r\n' "$reply"
    done

    # Send the current command (GETPIN or CONFIRM)
    printf '%s\r\n' "$current_cmd" >&"${PTY[1]}"

    # Proxy everything from here on: pinentry-tty ↔ agent
    # First drain pinentry-tty's response to the current command
    while IFS= read -r reply <&"${PTY[0]}"; do
        printf '%s\r\n' "$reply"
        # Stop after OK or ERR (end of command response)
        [[ $reply == OK* || $reply == ERR* ]] && break
    done

    # Proxy remaining commands until BYE
    while IFS= read -r line; do
        printf '%s\r\n' "$line" >&"${PTY[1]}"
        while IFS= read -r reply <&"${PTY[0]}"; do
            printf '%s\r\n' "$reply"
            [[ $reply == OK* || $reply == ERR* ]] && break
        done
        [[ $line == BYE* ]] && break
    done

    wait "${PTY_PID}" 2>/dev/null
    exit 0
}

# ── GETPIN via Emacs ─────────────────────────────────────────────────
do_getpin_emacs() {
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

# ── GETPIN dispatch ──────────────────────────────────────────────────
do_getpin() {
    if [[ -n "$ttyname" && -c "$ttyname" ]]; then
        handoff_to_pinentry_tty "GETPIN"
    elif [[ -S "$SOCK" ]] && timeout 5 "$EMACSCLIENT" --socket-name "$SOCK" --eval 't' >/dev/null 2>&1; then
        do_getpin_emacs
    else
        emit "ERR 83886179 No pinentry available <no-tty-no-emacs>"
    fi
}

# ── CONFIRM via Emacs ────────────────────────────────────────────────
do_confirm_emacs() {
    local eD expr result
    eD=$(elisp_escape "${desc:-Confirm}")
    expr="(my/pinentry-yes-or-no-p ${eD})"
    if result=$(timeout 120 "$EMACSCLIENT" --socket-name "$SOCK" --eval "$expr" 2>/dev/null) && [[ $result == "t" ]]; then
        emit "OK"
    else
        emit "ERR 83886194 Not confirmed <emacs>"
    fi
}

do_confirm() {
    if [[ -n "$ttyname" && -c "$ttyname" ]]; then
        handoff_to_pinentry_tty "CONFIRM"
    elif [[ -S "$SOCK" ]]; then
        do_confirm_emacs
    else
        emit "ERR 83886194 Not confirmed <no-tty-no-emacs>"
    fi
}

# ── Main Assuan loop ─────────────────────────────────────────────────
emit "OK Pleased to meet you, process $$"
while IFS= read -r line; do
    line=${line%$'\r'}
    cmd=${line%% *}
    arg=""; [[ $line == *" "* ]] && arg="${line#* }"
    case $cmd in
        SETDESC)        desc=$(pct_decode "$arg");        protocol_buf+=("$line"); emit "OK" ;;
        SETPROMPT)      prompt=$(pct_decode "$arg");      protocol_buf+=("$line"); emit "OK" ;;
        SETERROR)       errmsg=$(pct_decode "$arg");      protocol_buf+=("$line"); emit "OK" ;;
        SETTITLE|SETOK|SETCANCEL|SETNOTOK|SETKEYINFO|SETREPEAT|SETREPEATERROR)
                        protocol_buf+=("$line"); emit "OK" ;;
        OPTION)
            if [[ $arg == ttyname=* ]]; then
                ttyname="${arg#ttyname=}"
            fi
            protocol_buf+=("$line"); emit "OK" ;;
        NOP)            emit "OK" ;;
        RESET)          desc=""; prompt=""; errmsg=""; ttyname=""; protocol_buf=(); emit "OK" ;;
        GETINFO)
            case $(pct_decode "$arg") in
                pid)            emit "D $$";                    emit "OK" ;;
                version)        emit "D 1.3.0";                 emit "OK" ;;
                flavor)         emit "D emacs-frame";           emit "OK" ;;
                pinentry-info)  emit "D pinentry-emacs-frame";  emit "OK" ;;
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
