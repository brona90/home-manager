---
description: Targeted patch / re-test / re-review loop for changes after the main Large Changes workflow (manual QA findings, PR review comments, small bugs) — without restarting the full workflow.
argument-hint: <what to fix / change>
---

# Iteration Loop (Patch / Re-test / Re-review)

Use this for targeted changes after a feature has been built — manual QA findings, PR
review comments, or small bugs — without restarting the full Large Changes workflow.

**Patch request:** $ARGUMENTS

The **Spec Packet** remains the single source of truth at `.claude/state/spec-packet.md`.
Agents read it from disk; do not paste it verbatim into invocations.

## Step 1 — Create Patch Packet
Create a **Patch Packet** (include it verbatim when invoking agents below):
- What to change / fix (bullets)
- Expected behavior (testable)
- Scope constraint (keep change minimal)
- References (PR comment links, file/line, repro steps)
- Does this change acceptance criteria or non-goals? (Yes/No)
  - If **Yes**: have **feature-implementation-planner** update the Spec Packet
    (`.claude/state/spec-packet.md`) first, then continue.

## Step 2 — Implement Patch
Invoke **code-change-advisor** with the Patch Packet (verbatim). It reads the Spec Packet
from disk. It makes the smallest fix that satisfies the Patch Packet, commits, and reports
diff highlights.

## Step 3 — Validate Patch
Invoke **test-planner** with the Patch Packet (verbatim) and `git diff development`. It
reads the Spec Packet from disk, adds/adjusts targeted tests, runs targeted tests + full
suite, and reports per-test summaries.

## Step 4 — Re-Review (as needed)
- If prompted by PR review comments: re-invoke **pr-review-architect** on the same PR to
  confirm the issues are resolved.
- If prompted by spec/design concerns: re-invoke **spec-alignment-reviewer** to confirm alignment.

Repeat the Iteration Loop until approved.
