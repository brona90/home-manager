#!/usr/bin/env bash
# claude-kg auto-capture (SessionEnd hook).
#
# When a Claude session ends, this distills durable facts from the session transcript
# into the knowledge graph, in the background, without blocking the end of your session.
#
# Two backends (set CLAUDE_KG_CAPTURE_BACKEND):
#   local  (default) — a LOCAL Ollama model extracts structured facts, written
#                       deterministically by kg-capture. Free, offline, no agent.
#   claude           — a detached headless Claude reads the transcript and writes via
#                       MCP tools. Higher quality, costs API tokens, spawns an agent.
#
# Recursion guard (claude backend only): the capture agent runs with CLAUDE_KG_CAPTURE=1,
# which makes this hook a no-op so the capture session's own end can't re-trigger it.
set -uo pipefail

[ -n "${CLAUDE_KG_CAPTURE:-}" ] && exit 0

BACKEND="${CLAUDE_KG_CAPTURE_BACKEND:-local}"
DATA_DIR="${CLAUDE_KG_DATA_DIR:-$HOME/.local/share/claude-kg}"
LOG="$DATA_DIR/capture.log"
LOCK="$DATA_DIR/capture.lock"
# Upper bound on how long a queued capture waits for the one ahead of it. A single
# run is bounded by capture_local.py's 300s Ollama read timeout, so this lets a
# short queue drain; past it we drop the capture and say so in the log.
LOCK_WAIT="${CLAUDE_KG_CAPTURE_LOCK_WAIT:-1800}"
mkdir -p "$DATA_DIR"

# Body of every detached capture: take the exclusive capture lock on fd 9, then
# exec the real command (the lock survives exec and is released when it exits).
# Concurrent captures hammer the same local Ollama model and time out mid-run
# (httpx.ReadTimeout), silently writing a partially extracted session. Now that
# SessionEnd fires from both Windows and WSL, overlap is routine. We BLOCK rather
# than skip-if-locked: this body is already detached, and the hook itself returns
# immediately either way, so waiting costs the user nothing, whereas skipping would
# lose that session permanently. flock comes from util-linux, already on the wrapper
# PATH (package.nix). Kept as a string because setsid/nohup need a real command and a
# shell function cannot be handed to bash -c. It is single-quoted, so it must contain
# no apostrophes.
#
# shellcheck disable=SC2016
# The single quotes are the point: $1 and $@ must reach `bash -c` unexpanded and
# be bound to ITS positional parameters. Expanding them here would bake this
# script's own arguments into the lock wrapper and break it.
LOCK_RUN='if flock -w "$1" 9; then shift; exec "$@"; fi
printf "%s capture skipped: capture lock busy for more than %ss\n" "$(date -u +%FT%TZ)" "$1"'

# --- read hook payload from stdin ---
payload="$(cat)"
# One field per line, one `read` each. A single `read -r a b c` splits on IFS, so any
# space in transcript_path or cwd shifted every later field: cwd got truncated at the
# space and was still written to the graph as durable observation provenance, or the
# transcript path got truncated so the -f guard below dropped the session silently.
# Windows paths (My Documents, Program Files, OneDrive - Company) routinely contain
# spaces. Python normalises embedded CR/LF so the three-line contract always holds;
# malformed or absent JSON yields three empty fields, which the guard below treats
# exactly as it did before.
transcript=""
cwd=""
reason=""
{
  IFS= read -r transcript
  IFS= read -r cwd
  IFS= read -r reason
} < <(printf '%s' "$payload" | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}
for _k in ("transcript_path", "cwd", "reason"):
    _v = d.get(_k, "")
    if not isinstance(_v, str):
        _v = ""
    sys.stdout.write(_v.replace("\r", " ").replace("\n", " ") + "\n")
' 2>/dev/null)

# Skip if no transcript, missing, or too small to hold anything durable.
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0
bytes=$(wc -c < "$transcript" 2>/dev/null || echo 0)
[ "$bytes" -lt 2000 ] && exit 0

echo "$(date -u +%FT%TZ) capture start (backend=$BACKEND, reason=$reason, bytes=$bytes) $transcript" >> "$LOG"

if [ "$BACKEND" = "claude" ]; then
  # Injection surface, by design: the transcript handed to this agent contains
  # whatever the session pulled in - fetched web pages, file contents, tool
  # output - and the agent reading it holds graph-write tools. Text in a
  # transcript can therefore try to talk this agent into writing attacker-chosen
  # "facts" into long-term memory, which later sessions will recall as trusted.
  # The allow-list below is the mitigation: it grants Read plus kg writes and
  # nothing else, so a successful injection can corrupt memory but cannot run
  # commands or touch the filesystem. Keep it that way, and prefer the default
  # local backend unless the quality difference actually matters.
  MODEL="${CLAUDE_KG_CAPTURE_MODEL:-claude-haiku-4-5-20251001}"
  CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
  ALLOWED="Read mcp__claude-kg__kg_recall mcp__claude-kg__kg_search mcp__claude-kg__kg_get mcp__claude-kg__kg_upsert_entity mcp__claude-kg__kg_add_observations mcp__claude-kg__kg_relate"
  read -r -d '' PROMPT <<PROMPT_EOF
You are a memory-capture agent for the claude-kg knowledge graph. Read the transcript at
${transcript}. Extract only DURABLE, REUSABLE facts (project purpose/architecture,
decisions and their rationale, how systems connect, stable config, lasting user
preferences). For each, call kg_recall first to check for an existing entity, then
kg_add_observations or kg_upsert_entity with source="${cwd}", and kg_relate to link
entities. Skip secrets, transient state, and trivia. If nothing durable, reply
"nothing to capture".
PROMPT_EOF
  CLAUDE_KG_CAPTURE=1 setsid nohup bash -c "$LOCK_RUN" kg-capture-lock \
    "$LOCK_WAIT" "$CLAUDE_BIN" -p "$PROMPT" \
    --model "$MODEL" --allowedTools "$ALLOWED" --permission-mode acceptEdits \
    9>>"$LOCK" >> "$LOG" 2>&1 < /dev/null &
else
  # local backend: purely local extraction + deterministic writes (no agent, no API).
  # kg-capture is provided by the claude-kg package (KG_CAPTURE_BIN set by its wrapper).
  KG_CAPTURE="${KG_CAPTURE_BIN:-kg-capture}"
  setsid nohup bash -c "$LOCK_RUN" kg-capture-lock \
    "$LOCK_WAIT" "$KG_CAPTURE" "$transcript" "$cwd" \
    9>>"$LOCK" >> "$LOG" 2>&1 < /dev/null &
fi

exit 0
