#!/usr/bin/env bash
# Snapshot every claude-kg collection and prune to the newest $KEEP per collection.
# Snapshots land in the Qdrant container's mounted snapshots volume.
# Run by the kg-snapshot systemd timer; safe to run by hand any time.
set -uo pipefail

QDRANT="${QDRANT_URL:-http://localhost:6333}"
KEEP="${KEEP:-7}"
DATA_DIR="${CLAUDE_KG_DATA_DIR:-$HOME/.local/share/claude-kg}"
LOG="$DATA_DIR/snapshot.log"
mkdir -p "$DATA_DIR"
PY="$(command -v python3 || echo python3)"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

for c in entities relations documents; do
  if curl -sf -X POST "$QDRANT/collections/$c/snapshots" >/dev/null; then
    echo "$(ts) snapshot $c ok" >> "$LOG"
  else
    echo "$(ts) snapshot $c FAILED" >> "$LOG"
    continue
  fi
  # prune: list snapshots oldest-first, delete all but the newest $KEEP
  old=$(curl -sf "$QDRANT/collections/$c/snapshots" \
        | "$PY" -c "import sys,json; r=json.load(sys.stdin)['result']; r.sort(key=lambda x:x['creation_time']); [print(x['name']) for x in r[:-$KEEP]]" 2>/dev/null)
  for n in $old; do
    curl -sf -X DELETE "$QDRANT/collections/$c/snapshots/$n" >/dev/null \
      && echo "$(ts) pruned $c/$n" >> "$LOG"
  done
done
