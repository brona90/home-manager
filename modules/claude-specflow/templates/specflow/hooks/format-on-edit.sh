#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write) — auto-format the file that was just edited.
#
# Formatting is non-critical: this hook is best-effort and always exits 0 so it never
# blocks the agent. It dispatches by file extension and only runs a formatter that is
# actually installed. Adjust the dispatch table to your stack's real formatters.
#
# Protocol: reads tool-call JSON on stdin; tool_input.file_path is the edited file.
set -euo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

have() { command -v "$1" >/dev/null 2>&1; }

case "$file" in
  *.cs)
    # .NET — format just the touched file's project is expensive; format the file in place if a tool exists.
    if have dotnet; then dotnet format --include "$file" >/dev/null 2>&1 || true; fi
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.scss|*.html|*.md)
    if have prettier; then prettier --write "$file" >/dev/null 2>&1 || true
    elif have npx; then npx --no-install prettier --write "$file" >/dev/null 2>&1 || true; fi
    ;;
  *.py)
    if have ruff; then ruff format "$file" >/dev/null 2>&1 || true
    elif have black; then black "$file" >/dev/null 2>&1 || true; fi
    ;;
  *.sh)
    if have shfmt; then shfmt -w "$file" >/dev/null 2>&1 || true; fi
    ;;
esac

exit 0
