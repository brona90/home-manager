#!/usr/bin/env bash
# Functional test matrix for templates/specflow/hooks/branch-policy.sh.
#
# Usage: branch-policy-matrix.sh <path-to-branch-policy.sh>
#
# WHY THIS EXISTS
#
# branch-policy.sh has to infer, from a command string it is given before that command runs,
# which directory a git commit will land in. That inference is approximate, and the hook is a
# safety control: an inference bug in one direction is an annoyance (a commit on a feature
# branch gets blocked) and in the other direction is a hole (a commit lands on master).
#
# Both have already happened. The hook shipped reading the branch with a bare `git rev-parse`
# in its OWN cwd, so every worktree commit was blocked — the false-positive direction. The
# first attempt to fix that (PR #6, closed unmerged) resolved a single directory and fell back
# to `|| true`, so any parse miss became a silent ALLOW; it let `cd <worktree> && cd <main> &&
# git commit` and `cd <nonexistent> && git commit` put a commit on master — the hole direction.
# The matrix below covers both directions because fixing either one alone looks like success.
#
# This file is deliberately OUTSIDE templates/specflow/: that directory is copied verbatim
# into every repo that runs /specflow, and those repos do not need the hook's own test suite.
#
# VALIDATED BY MUTATION. Each of these deliberate breakages was confirmed to turn this matrix
# red, so a green run means something:
#   1. branch read in the hook's own cwd          -> W1 W2 P3 M4 L1-L6 U1 U2
#   2. unresolvable directory falls open          -> A4 A5 A10
#   3. legacy grep fallback removed               -> A11
#   4. token-based force-push detection removed   -> F1 F2
#   5. tokenizer ignores double quotes            -> A12 L1
#   6. only the first commit in a line is checked -> M1 M2 M3
#   7. parens no longer separate commands         -> L4
#   8. tilde no longer expanded                   -> L3
set -uo pipefail

HOOK="${1:?usage: branch-policy-matrix.sh <path-to-branch-policy.sh>}"
case "$HOOK" in
  /*) ;;
  *) HOOK="$PWD/$HOOK" ;;
esac
[ -r "$HOOK" ] || {
  echo "no such hook: $HOOK" >&2
  exit 2
}

# Hermetic HOME. The hook expands a leading ~ itself, so the tilde case has to point at a
# fixture; overriding HOME keeps that fixture out of the real home directory.
#
# HOME alone is not enough to detach git from the caller's configuration: git also reads
# $XDG_CONFIG_HOME/git/config, and XDG_CONFIG_HOME is set independently of HOME. On this repo's
# own machine that config carries commit.gpgsign=true, so the fixture's seed commit reached for
# a YubiKey and the suite hung on a PIN prompt with no output. GIT_CONFIG_GLOBAL/SYSTEM pin
# both files explicitly, which is the only form that closes every route.
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME
: >"$ROOT/gitconfig"
export GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0
FX="$HOME/fx"

git init -q -b master "$FX/main"
git -C "$FX/main" config user.email hook-test@example.invalid
git -C "$FX/main" config user.name "hook test"
git -C "$FX/main" config commit.gpgsign false
echo seed >"$FX/main/a.txt"
git -C "$FX/main" add a.txt
git -C "$FX/main" commit -qm seed
git -C "$FX/main" worktree add -q -b feature/x "$FX/wt"
git -C "$FX/main" worktree add -q -b development "$FX/wtdev"
git -C "$FX/main" worktree add -q -b feature/spaced "$FX/my wt"
git -C "$FX/main" worktree add -q --detach "$FX/detached"
git init -q -b master "$FX/fresh" # unborn HEAD: no commits yet
mkdir -p "$FX/plain"              # a directory that is not a repo at all

pass=0
fail=0

# Feed one command to the hook as the Bash PreToolUse payload, from a chosen cwd, and compare
# the decision against what policy requires.
run_case() {
  local expected="$1" cwd="$2" cmd="$3" label="$4"
  local out rc verdict
  out="$(printf '%s' "$cmd" | jq -Rs '{tool_input:{command:.}}' | (cd "$cwd" && bash "$HOOK") 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    verdict="ERROR(rc=$rc)"
  elif printf '%s' "$out" | grep -q '"deny"'; then
    verdict="DENY"
  else
    verdict="ALLOW"
  fi
  if [ "$verdict" = "$expected" ]; then
    printf 'PASS  %-6s  %s\n' "$verdict" "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL  got=%-12s want=%-6s  %s\n' "$verdict" "$expected" "$label"
    fail=$((fail + 1))
  fi
}

echo "--- core protections ---"
run_case DENY "$FX/main" 'git commit -m x' 'C1  bare commit, cwd=main(master)'
run_case DENY "$FX/main" "cd $FX/main && git commit -m x" 'C2  cd main && commit'
run_case DENY "$FX/main" 'git push --force origin feature/x' 'C3  force push --force'
run_case DENY "$FX/main" 'git push -f origin feature/x' 'C4  force push -f'
run_case DENY "$FX/main" 'git push --force-with-lease origin feature/x' 'C5  force push --force-with-lease'
run_case DENY "$FX/main" 'git push origin master' 'C6  direct push to master'
run_case DENY "$FX/main" 'git push origin development' 'C7  direct push to development'

echo "--- the worktree false positive this hook was fixed for ---"
run_case ALLOW "$FX/main" "cd $FX/wt && git commit -m x" 'W1  cd worktree(feature) && commit'
run_case ALLOW "$FX/main" "git -C $FX/wt commit -m x" 'W2  git -C worktree(feature) commit'
run_case ALLOW "$FX/wt" 'git commit -m x' 'W3  bare commit, cwd=worktree(feature)'

echo "--- a protected branch reached THROUGH a worktree is still protected ---"
run_case DENY "$FX/main" "cd $FX/wtdev && git commit -m x" 'P1  cd worktree(development) && commit'
run_case DENY "$FX/main" "git -C $FX/wtdev commit -m x" 'P2  git -C worktree(development) commit'
run_case DENY "$FX/wt" "cd $FX/main && git commit -m x" 'P3  cwd=worktree, cd main && commit'

echo "--- adversarial: directory resolution must not fall open ---"
run_case DENY "$FX/main" "cd $FX/wt && cd $FX/main && git commit -m x" 'A1  cd wt && cd main && commit (last cd wins)'
run_case DENY "$FX/main" "cd $FX/plain && cd $FX/main && git commit -m x" 'A2  cd nonrepo && cd main && commit'
run_case DENY "$FX/main" "git -C $FX/wt log --oneline && git commit -m x" 'A3  -C on a DIFFERENT command, commit in main'
run_case DENY "$FX/main" "cd $FX/nonexistent && git commit -m x" 'A4  cd to a nonexistent dir'
run_case DENY "$FX/main" "cd $FX/plain && git commit -m x" 'A5  cd to a dir that is not a repo'
run_case DENY "$FX/main" "git commit -m x && cd $FX/wt" 'A6  commit first, cd afterwards'
run_case DENY "$FX/main" "echo cd $FX/wt && git commit -m x" 'A7  cd is an argument to echo, not a cd'
run_case DENY "$FX/main" "git commit -m \"see cd $FX/wt\"" 'A8  worktree path inside the commit message'
run_case DENY "$FX/main" "echo \"a && cd $FX/wt\" && git commit -m x" 'A9  quoted && cd inside an argument'
run_case DENY "$FX/main" "git --git-dir=$FX/wt/.git commit -m x" 'A10 --git-dir: a relocation route not modelled'
run_case DENY "$FX/main" 'bash -c "git commit -m x"' 'A11 commit nested inside bash -c'
run_case DENY "$FX/main" "echo \"note && cd $FX/wt \" && git commit -m x" 'A12 quoted cd to a VALID dir in an argument'

echo "--- several git invocations in one command line: every one is checked ---"
run_case DENY "$FX/main" "cd $FX/wt && git commit -m a && cd $FX/main && git commit -m b" 'M1  safe commit, then one on master'
run_case DENY "$FX/main" "git -C $FX/wt commit -m a && git -C $FX/wtdev commit -m b" 'M2  -C feature, then -C development'
run_case DENY "$FX/main" "cd $FX/wt && git commit -m a && git -C $FX/main commit -m b" 'M3  cd feature, then -C master'
run_case ALLOW "$FX/main" "cd $FX/wt && git commit -m a && git -C \"$FX/my wt\" commit -m b" 'M4  two commits, both feature branches'

echo "--- force push hidden behind -C (the adjacency-grep blind spot) ---"
run_case DENY "$FX/main" "git -C $FX/wt push --force origin master" 'F1  -C + push --force'
run_case DENY "$FX/main" "git -C $FX/wt push -f origin feature/x" 'F2  -C + push -f'
run_case DENY "$FX/main" "cd $FX/wt && git push --force-with-lease" 'F3  cd wt && push --force-with-lease'

echo "--- legitimate worktree spellings must keep working ---"
run_case ALLOW "$FX/main" "cd \"$FX/my wt\" && git commit -m x" 'L1  quoted path containing a space'
run_case ALLOW "$FX/main" 'cd ../wt && git commit -m x' 'L2  relative cd'
run_case ALLOW "$FX/main" 'cd ~/fx/wt && git commit -m x' 'L3  tilde path'
run_case ALLOW "$FX/main" "(cd $FX/wt && git commit -m x)" 'L4  subshell'
run_case ALLOW "$FX/main" "cd $FX/wt && git add -A && git commit -m x" 'L5  cd wt && add && commit'
run_case ALLOW "$FX/main" "cd $FX/wt; git commit -m x" 'L6  semicolon separator'

echo "--- unborn and detached HEAD must not become new false positives ---"
run_case ALLOW "$FX/main" "cd $FX/fresh && git commit -m init" 'U1  first commit in a fresh repo (unborn master)'
run_case ALLOW "$FX/main" "cd $FX/detached && git commit -m x" 'U2  commit on a detached HEAD'

echo "--- unrelated commands must pass through untouched ---"
run_case ALLOW "$FX/main" 'ls -la' 'N1  not a git command'
run_case ALLOW "$FX/main" 'git status' 'N2  git status on master'
run_case ALLOW "$FX/main" 'git push origin feature/x' 'N3  ordinary push of a feature branch'

echo
echo "SUMMARY: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
