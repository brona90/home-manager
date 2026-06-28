#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — deterministic database safety net.
#
# Blocks, regardless of model intent:
#   1. Destructive SQL: DROP TABLE/DATABASE/SCHEMA, TRUNCATE, DELETE/UPDATE without WHERE
#   2. EF / migration "apply" commands (database update / migrate) — migrations go through
#      the pipeline (dev) only, never run ad hoc from the agent
#   3. Any DB command whose target looks like test/staging/prod (see PATTERNS below)
#
# These mirror the prose rules in CLAUDE.md, but as a *deterministic* backstop: prompts are
# probabilistic, hooks are not. Tune PROD_TEST_PATTERN to your real host/connection names —
# per the "No Default Values" rule, make this explicit for your environment.
#
# Protocol: read tool-call JSON on stdin; to block, emit a deny decision and exit 0.
set -euo pipefail

# >>> CONFIGURE FOR YOUR ENVIRONMENT (do not leave as guesses) <<<
# Hosts / connection identifiers that must never be touched ad hoc by the agent.
PROD_TEST_PATTERN='prod|production|staging|stage|[^a-z]test[^a-z]|\.rds\.|amazonaws\.com'
# <<< end configuration >>>

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

# Nothing to inspect (not a Bash command, or empty) -> allow.
[ -z "$cmd" ] && exit 0

deny() {
  # $1 = human-readable reason
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

# 1) Destructive DDL/DML ------------------------------------------------------
if printf '%s' "$lc" | grep -Eq 'drop[[:space:]]+(table|database|schema)'; then
  deny "Blocked: DROP TABLE/DATABASE/SCHEMA is a destructive operation. If this is truly intended, the user must run it manually."
fi
if printf '%s' "$lc" | grep -Eq 'truncate[[:space:]]+(table[[:space:]]+)?'; then
  deny "Blocked: TRUNCATE is a destructive operation. If truly intended, the user must run it manually."
fi
# DELETE / UPDATE without a WHERE clause (heuristic: statement up to ; has no 'where').
if printf '%s' "$lc" | grep -Eq 'delete[[:space:]]+from[[:space:]]+[^;]*' \
   && ! printf '%s' "$lc" | grep -Eq 'delete[[:space:]]+from[[:space:]]+[^;]*where'; then
  deny "Blocked: DELETE without a WHERE clause. Add a WHERE clause, or the user must run it manually if a full-table delete is intended."
fi
if printf '%s' "$lc" | grep -Eq 'update[[:space:]]+[a-z0-9_.\"]+[[:space:]]+set[[:space:]]+[^;]*' \
   && ! printf '%s' "$lc" | grep -Eq 'update[[:space:]]+[a-z0-9_.\"]+[[:space:]]+set[[:space:]]+[^;]*where'; then
  deny "Blocked: UPDATE without a WHERE clause. Add a WHERE clause, or the user must run it manually if a full-table update is intended."
fi

# 2) Migration apply / pipeline-only ------------------------------------------
if printf '%s' "$lc" | grep -Eq '(dotnet[[:space:]]+ef|ef)[[:space:]]+database[[:space:]]+update' \
   || printf '%s' "$lc" | grep -Eq 'migrate[[:space:]]+(up|--?env|deploy)'; then
  deny "Blocked: applying migrations from the agent. Migrations are applied via the pipeline (DEV only); never to test/prod manually."
fi

# 3) Test/prod DB targeting ---------------------------------------------------
if printf '%s' "$lc" | grep -Eq 'psql|pg_dump|pg_restore|dotnet[[:space:]]+ef|sqlcmd|mysql' \
   && printf '%s' "$lc" | grep -Eiq "$PROD_TEST_PATTERN"; then
  deny "Blocked: database command appears to target a test/staging/prod resource. Default to DEV only; the user must run non-dev DB operations manually."
fi

# Allowed.
exit 0
