---
description: Scaffold the "specflow" multi-agent dev system (planner → coder → spec-reviewer → test-planner → PR-reviewer, with an on-disk Spec Packet and deterministic safety hooks) into the current repository. Runs ONLY when explicitly invoked.
argument-hint: "[target repo path — defaults to the current working directory]"
---

# specflow — scaffold the multi-agent dev system into a repo

You are installing the **specflow** system into a repository. The canonical source of truth
is the template at `~/.claude/templates/specflow/`. **Copy from that template — do not
regenerate the files from memory** (avoids drift). Only act when the user invokes this
command or explicitly asks to "use/set up specflow"; never run it on your own.

**Target repo:** `$ARGUMENTS` if provided, otherwise the current working directory. Confirm
the resolved target path with the user before writing anything.

## What specflow is (so you can explain it if asked)
A plan→build→review→test→PR pipeline split across 5 subagents, coordinated by two opt-in
slash commands, with a frozen **Spec Packet** (`.claude/state/spec-packet.md`) as the single
source of truth and **hooks** that deterministically block dangerous DB/git actions. Heavy
process is opt-in; small changes stay friction-free.

## Installation steps

1. **Resolve & confirm the target.** Verify the target is a git repo root (look for `.git`).
   If it isn't, tell the user and ask whether to proceed anyway or `git init` first.

2. **Copy the bundle, merging — never clobber.** For each item under the template's
   `.claude/`:
   - If the file/dir does **not** exist in the target → copy it in.
   - If it **already exists** → do NOT overwrite silently. Show the difference and ask the
     user whether to keep theirs, take the template's, or merge. This matters most for:
     - `.claude/settings.json` — **merge the `hooks` blocks** (combine the `PreToolUse` /
       `PostToolUse` arrays) rather than replacing the file. Use `jq` to merge and validate.
     - existing agents/commands with the same name.
   - Always run `chmod +x <target>/.claude/hooks/*.sh` after copying.
   - Create an empty `.claude/state/` directory (the planner writes the Spec Packet there at
     runtime; do not copy any stale packet).

3. **Merge CLAUDE.md.** The template ships `CLAUDE.snippet.md`.
   - If the target has no `CLAUDE.md` → write the snippet as the new `CLAUDE.md`.
   - If it has one → append the snippet's sections under a clear `# specflow` heading, and
     reconcile conflicts with the user (don't duplicate an existing Git or DB section —
     merge them).

4. **Fill the three project-specific config values** (the system's "no default values" rule
   means these must be explicit, not guessed). Inspect the repo to propose real values, then
   confirm with the user before writing:
   - `.claude/hooks/db-safety.sh` → `PROD_TEST_PATTERN`: real prod/test DB host & connection
     identifiers (grep for connection strings, appsettings, env files, `*.tf`).
   - `.claude/hooks/branch-policy.sh` → `PROTECTED`: the repo's protected branches (check the
     default branch via `git symbolic-ref refs/remotes/origin/HEAD` or `git branch`).
   - `.claude/hooks/format-on-edit.sh` → dispatch table: the repo's actual formatters (check
     `package.json`, `.editorconfig`, `*.csproj`, `pyproject.toml`, CI configs).
   Also skim the merged `CLAUDE.md` and strip assumptions that don't apply (e.g. Step
   Functions, pgpass, the `feature → development → master` flow) — adjust to this repo's reality.

5. **Verify before declaring done:**
   - `jq -e . <target>/.claude/settings.json` (valid JSON).
   - Each `.claude/agents/*.md` has closed `---` frontmatter with `name/description/tools/model`.
   - Behavioral hook check, e.g.:
     `echo '{"tool_input":{"command":"psql prod -c \"DROP TABLE x\""}}' | <target>/.claude/hooks/db-safety.sh`
     → expect a `deny` decision; a benign `SELECT ... LIMIT` → no deny.
   - `wc -l <target>/CLAUDE.md` is reasonable (< ~200 lines).

6. **Tell the user the last manual step:** restart / reopen Claude Code in that repo so the
   agents, commands, and hooks load, and approve the hooks when prompted. Then `/large-change`
   and `/iterate` will be available.

## After install
Summarize: what was copied, what was merged vs skipped, the exact config values you set (and
why), and the verification results. Remind them the workflow is opt-in: `/large-change
<request>` for features, `/iterate <fix>` for follow-ups, and plain prompts for small edits.
