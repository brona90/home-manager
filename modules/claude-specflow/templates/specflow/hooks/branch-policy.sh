#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — deterministic git branch policy.
#
# Blocks:
#   1. Commits made while on a protected branch (master / main / development)
#   2. Force pushes (git push --force / -f / --force-with-lease)
#   3. Direct pushes to a protected branch
#
# Per the repo Git model: feature branches -> development -> master. Work happens on feature
# branches; integration branches are updated via merged PRs, not direct commits/pushes.
#
# Protocol: read tool-call JSON on stdin; to block, emit a deny decision and exit 0.
set -euo pipefail

# >>> CONFIGURE: protected branches for your repo <<<
PROTECTED='master|main|development|develop'
# <<< end configuration >>>

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Current branch (best effort; empty if not in a repo).
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

# 1) Force push -> always blocked.
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push' \
   && printf '%s' "$cmd" | grep -Eq -- '--force-with-lease|--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$)'; then
  deny "Blocked: force push. Rewriting shared history is not allowed; reconcile with a normal push/merge instead."
fi

# 2) Direct push to a protected branch (git push <remote> <protected>).
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push' \
   && printf '%s' "$cmd" | grep -Eq "[[:space:]]($PROTECTED)([[:space:]]|:|$)"; then
  deny "Blocked: direct push to a protected branch ($PROTECTED). Use a feature branch and open a PR."
fi

# 3) Commit while on a protected branch.
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+commit' \
   && printf '%s\n' "$branch" | grep -Eq "^($PROTECTED)$"; then
  deny "Blocked: commit on protected branch '$branch'. Create a feature branch first (feature/...), then commit."
fi

exit 0
