---
description: Run the full Large Changes workflow (plan → implement → migrate(dev) → deploy(dev) → spec-align → tests → PR → review → merge) for a feature, multi-file change, or anything with design-doc implications.
argument-hint: <feature or change request>
---

# Large Changes Workflow

Run this guided, multi-step workflow for the request below. This workflow is **opt-in** —
use it only for features, multi-file changes, or anything with design-doc implications.
Small changes (1–2 lines, config values, no design-doc risk) do NOT need this; just make
the change on a feature branch, have `test-planner` cover it, and merge.

**Request:** $ARGUMENTS

## Handoff artifact: the Spec Packet
The **Spec Packet** is the single source of truth for this change. It lives on disk at
`.claude/state/spec-packet.md`. The planner writes it; all other agents **read it from
disk**. Do NOT paste the full Spec Packet into every agent invocation — pass the request,
constraints, and the path. Only `feature-implementation-planner` may update it; everyone
else treats it as read-only.

---

## Step 1 — Planning (conversational loop until approved)
1. Invoke **feature-implementation-planner** with the request.
2. Run a **Planner Debrief** (do NOT just summarize):
   - Present the planner's key details: acceptance criteria, non-goals/scope boundaries,
     2–4 approaches with trade-offs, files/modules likely impacted, risks + rollout/rollback notes.
   - Extract **Decision Points**: the 3–7 choices the user must decide (e.g., "Approach A vs B",
     "schema change vs no schema change", "sync vs async", "feature flag or not").
   - Ask **targeted questions** only where the user's preference is needed.
   - Prefer concrete bullets over prose. End with decision points + questions, not "continue?".
3. Wait for user input: approve one approach as-is, provide direction changes, or request more options.
4. If the user wants changes/new options: re-invoke the planner with the feedback and constraints; repeat Step 1.
5. **Upon approval**, the planner writes the Spec Packet to `.claude/state/spec-packet.md`.
   Confirm the file exists before proceeding.

## Step 2 — Implementation (code-change-advisor)
1. Invoke **code-change-advisor** with the request and any constraints decided in Step 1.
   It reads the Spec Packet from `.claude/state/spec-packet.md`.
2. The advisor will: create a feature branch; implement directly; make small reviewable
   commits; run build/lint/tests where applicable; summarize the diff (files touched + key behaviors).
3. Wait for user input: approve, or request adjustments (sent back to code-change-advisor).

## Step 3 — Database Migration (DEV ONLY, if required)
1. If code-change-advisor reported DB schema changes: create a migration and apply it to **DEV**.
2. NEVER apply migrations to test or prod manually. (Hooks block this; pipeline only.)
3. Report: migration name, files changed by migration, apply result (success/failure).
4. If migration requires backfill or non-trivial data transform: STOP and ask the user for
   explicit approval and a backfill plan before proceeding.

## Step 4 — Deploy to DEV (for manual testing)
1. Deploy all components to the DEV environment.
2. Report deployment results (success/failure for each).
3. If any deployment fails, stop and troubleshoot before proceeding.

## Step 5 — Spec Alignment & Design Doc Review (pre-tests)
1. Invoke **spec-alignment-reviewer** with the implementation changes
   (branch/commits and/or `git diff development`). It reads the Spec Packet from disk.
2. Scope: verify plan↔code alignment and design-doc compliance. Do NOT require tests to
   exist yet; if design docs require tests, note them as "Pending until Step 6" (not a violation).
3. If changes are required, route to the appropriate agent and re-run Step 5 until aligned.
4. Wait for user approval to proceed.

## Step 6 — Tests (test-planner executes + runs)
1. Invoke **test-planner** with the implementation changes (branch/commits and/or
   `git diff development`). It reads the Spec Packet from disk.
2. test-planner writes and integrates tests, runs the new/changed tests, runs the full
   suite (or CI-equivalent), and reports per-test summaries, commands+results, and gaps.
3. Ask the user: "Is coverage sufficient, or should we add/alter tests?"
4. If changes requested, re-invoke test-planner and repeat until approved.

## Step 7 — Spec Alignment (post-tests) — CONDITIONAL
Only run this step if the test work **touched non-test code** or changed design-doc-relevant
behavior. If tests were purely additive and touched no production code, **skip to Step 8**
and note the skip.
1. Re-invoke **spec-alignment-reviewer** with the updated changes + test changes (`git diff development`).
2. Scope: confirm any test requirements from design docs are now satisfied; confirm no
   spec/design drift was introduced by test work.
3. If changes required, route to code-change-advisor or test-planner and re-run until approved.

## Step 8 — Create PR
1. Ensure the feature branch contains approved implementation changes + approved tests.
2. Create a PR targeting `development`:
   - Clear, concise title describing the change.
   - Brief description: what changed, why, any rollout notes.
3. Do NOT perform a review here. Do NOT add comments/analysis. Do NOT merge.
4. Report only: PR link, branch name.

## Step 9 — PR Review (pr-review-architect comments + report back)
1. Invoke **pr-review-architect** on the PR from Step 8.
2. The agent locates the PR, reviews every changed file/line, posts actionable comments via
   the GitHub CLI, and outputs the full list of comments posted (verbatim).
3. Present the comments (verbatim) grouped by severity (🔴 / 🟡 / 🟢); call out any
   design-doc violations separately. Ask the user what to do next:
   - Send fixes to **code-change-advisor**, OR
   - Send plan changes to **feature-implementation-planner**, OR
   - Update/add docs via **spec-alignment-reviewer**, OR
   - Proceed without changes (with rationale).
   For targeted fix cycles, use `/iterate`.

## Step 10 — Merge PR
1. Confirm explicitly with the user that: all review comments are addressed or intentionally
   accepted, and code/tests/docs are in the desired final state.
2. Merge the PR into `development` using the repo's standard merge strategy (merge/squash/rebase).
3. Report only: PR link, merge commit hash.
4. End the workflow and wait for further user instruction.
