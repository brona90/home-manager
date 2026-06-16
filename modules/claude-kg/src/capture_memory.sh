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
mkdir -p "$DATA_DIR"

# --- read hook payload from stdin ---
payload="$(cat)"
read -r transcript cwd reason <<EOF
$(printf '%s' "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('transcript_path',''), d.get('cwd',''), d.get('reason',''))" 2>/dev/null)
EOF

# Skip if no transcript, missing, or too small to hold anything durable.
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0
bytes=$(wc -c < "$transcript" 2>/dev/null || echo 0)
[ "$bytes" -lt 2000 ] && exit 0

echo "$(date -u +%FT%TZ) capture start (backend=$BACKEND, reason=$reason, bytes=$bytes) $transcript" >> "$LOG"

if [ "$BACKEND" = "claude" ]; then
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
  CLAUDE_KG_CAPTURE=1 setsid nohup "$CLAUDE_BIN" -p "$PROMPT" \
    --model "$MODEL" --allowedTools "$ALLOWED" --permission-mode acceptEdits \
    >> "$LOG" 2>&1 < /dev/null &
else
  # local backend: purely local extraction + deterministic writes (no agent, no API).
  # kg-capture is provided by the claude-kg package (KG_CAPTURE_BIN set by its wrapper).
  KG_CAPTURE="${KG_CAPTURE_BIN:-kg-capture}"
  setsid nohup "$KG_CAPTURE" "$transcript" "$cwd" >> "$LOG" 2>&1 < /dev/null &
fi

exit 0
