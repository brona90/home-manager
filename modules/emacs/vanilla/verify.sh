#!/usr/bin/env bash
# verify.sh -- the emacs-vanilla gate.
#
# Promoted into the repo from /tmp, where the phase-3 version lived and where
# it was one `clear` away from being lost. Every later phase inherits it.
#
# WHAT IT IS FOR: this config disables package.el activation (see
# early-init.el), so nothing is reachable unless a `use-package' keyword said
# so. The failure mode is therefore always the same shape -- the key is bound,
# the popup shows a name, and the command is VOID when pressed. Nothing short
# of starting a real Emacs and asking it can catch that.
#
# THE RULE: a check that can only report PASS is not a check. Concretely, in
# this file that means:
#
#   * every linter's EXIT CODE is read. Grepping a linter's stdout for the word
#     "error" is how you get a gate that reports success while the tool is
#     failing to run at all.
#   * the daemon is started from the STORE config directory, not from
#     ~/.config/emacs -- otherwise it tests uncommitted working-tree files.
#   * `emacs --batch' is not used anywhere. Batch does not load init.el.
#
# Usage:  bash modules/emacs/vanilla/verify.sh
# Exit:   0 only if every stage passed.

# NOT `set -e`, deliberately: the point is to run EVERY stage and report all of
# them, not to stop at the first. Failures are accumulated in FAILURES.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$SCRIPT_DIR/../../.." && pwd)
SYSTEM=$(nix eval --raw --impure --expr 'builtins.currentSystem')
USER_NAME=${EMACS_VANILLA_VERIFY_USER:-gfoster}

FAILURES=0
SOCKET=emacs-vanilla-verify
WORK=$(mktemp -d)
REPORT="$WORK/report.txt"
DAEMON_LOG="$WORK/daemon.log"
DAEMON_PID=""

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

# Invoked by the EXIT trap below; shellcheck cannot see that.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "$DAEMON_PID" ]; then
    "$EMACSCLIENT" -s "$SOCKET" --eval '(kill-emacs)' >/dev/null 2>&1
    wait "$DAEMON_PID" 2>/dev/null
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# Resolve a linter that may or may not be in the profile. A linter that cannot
# be found is a FAILURE, never a skip -- silently skipping is exactly how a
# gate ends up green while checking nothing.
resolve_linter() {
  local tool=$1
  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
  elif nix run "nixpkgs#$tool" -- --help >/dev/null 2>&1; then
    printf 'nix-run:%s' "$tool"
  else
    printf ''
  fi
}

run_linter() {
  local tool=$1
  shift
  local resolved
  resolved=$(resolve_linter "$tool")
  if [ -z "$resolved" ]; then
    fail "$tool could not be resolved (not on PATH, not runnable from nixpkgs)"
    return
  fi
  local status=0
  if [ "${resolved#nix-run:}" != "$resolved" ]; then
    nix run "nixpkgs#$tool" -- "$@" || status=$?
  else
    "$resolved" "$@" || status=$?
  fi
  if [ "$status" -eq 0 ]; then
    pass "$tool (exit 0)"
  else
    fail "$tool exited $status"
  fi
}

# ---------------------------------------------------------------------------
say "0. preflight: nothing new is untracked"
# ---------------------------------------------------------------------------
# Flakes only see GIT-TRACKED files. A new lisp/*.el that has not been
# `git add`ed is simply absent from the store, and the daemon then fails with
# "Cannot open load file" -- which reads like a broken require, not like a
# missing `git add'. This has cost real time; it is a preflight now.
UNTRACKED=$(cd "$REPO" && git ls-files --others --exclude-standard -- modules/emacs/vanilla)
if [ -n "$UNTRACKED" ]; then
  fail "untracked files under modules/emacs/vanilla -- the flake will NOT see them:"
  printf '%s\n' "$UNTRACKED" | sed 's/^/        /'
  echo "        run: git add modules/emacs/vanilla"
else
  pass "no untracked files under modules/emacs/vanilla"
fi

# ---------------------------------------------------------------------------
say "1. nix lint (exit codes, not stdout)"
# ---------------------------------------------------------------------------
cd "$REPO" || exit 1
run_linter alejandra --check .
run_linter statix check .
run_linter deadnix --fail .
run_linter shellcheck "$SCRIPT_DIR/verify.sh"

# ---------------------------------------------------------------------------
say "2. nix build: the activation package"
# ---------------------------------------------------------------------------
# The real compile check. writeShellApplication runs shellcheck over every
# embedded script here, so a shell typo fails at build rather than at runtime.
if nix build "$REPO#homeConfigurations.\"$USER_NAME@$SYSTEM\".activationPackage" --no-link; then
  pass "activationPackage builds"
else
  fail "activationPackage build FAILED"
fi

# ---------------------------------------------------------------------------
say "3. a real daemon from the store config"
# ---------------------------------------------------------------------------
EMACS_OUT=$(nix build "$REPO#emacs-vanilla" --no-link --print-out-paths) || EMACS_OUT=""
CONFIG_DIR=$(nix eval --raw "$REPO#packages.$SYSTEM.emacs-vanilla.configDir") || CONFIG_DIR=""
nix build "$REPO#packages.$SYSTEM.emacs-vanilla.configDir" --no-link >/dev/null 2>&1

if [ -z "$EMACS_OUT" ] || [ -z "$CONFIG_DIR" ]; then
  fail "could not build emacs-vanilla / its configDir; skipping the daemon stage"
  printf '\n%d failure(s)\n' "$FAILURES"
  exit 1
fi
EMACSCLIENT="$EMACS_OUT/bin/emacsclient"
pass "config in store: $CONFIG_DIR"

# Every lisp/ file must have made it into the store. This is the preflight
# above, restated as a fact about the built artefact rather than about git.
for f in "$REPO"/modules/emacs/vanilla/config/lisp/*.el; do
  base=$(basename "$f")
  if [ -f "$CONFIG_DIR/lisp/$base" ]; then
    pass "store has lisp/$base"
  else
    fail "store is MISSING lisp/$base (git add it)"
  fi
done

# -- sample files, one per language ----------------------------------------
# Real content, not empty files: `sh--redirect-bash-ts-mode' guesses the shell
# from the shebang, so an empty sample.sh would prove nothing about the
# sh-mode -> bash-ts-mode remap.
SAMPLES="$WORK/samples"
mkdir -p "$SAMPLES"
printf '#!/usr/bin/env bash\nset -eu\necho hello\n'          > "$SAMPLES/sample.sh"
printf '#!/usr/bin/env zsh\nprint -r -- hello\n'             > "$SAMPLES/sample.zsh"
printf 'def main() -> int:\n    return 0\n'                  > "$SAMPLES/sample.py"
printf 'export const x = 1;\n'                               > "$SAMPLES/sample.js"
printf 'export const x = 1;\n'                               > "$SAMPLES/sample.mjs"
printf 'export const x: number = 1;\n'                       > "$SAMPLES/sample.ts"
printf 'export const C = () => <div>hi</div>;\n'             > "$SAMPLES/sample.tsx"
printf '{"a": 1}\n'                                          > "$SAMPLES/sample.json"
printf '[table]\nkey = "value"\n'                            > "$SAMPLES/sample.toml"
printf 'key: value\nlist:\n  - one\n'                        > "$SAMPLES/sample.yaml"
printf 'package main\n\nfunc main() {}\n'                     > "$SAMPLES/sample.go"
printf 'module example.com/m\n\ngo 1.22\n'                    > "$SAMPLES/go.mod"
printf 'fn main() { println!("hi"); }\n'                      > "$SAMPLES/sample.rs"
printf 'local function f() return 1 end\n'                    > "$SAMPLES/sample.lua"
printf 'class Sample { public static void main(String[] a) {} }\n' > "$SAMPLES/Sample.java"
printf '{ pkgs, ... }: { home.packages = [ pkgs.hello ]; }\n'  > "$SAMPLES/sample.nix"
printf 'main :: IO ()\nmain = putStrLn "hi"\n'                 > "$SAMPLES/sample.hs"
printf 'FROM debian:bookworm\nRUN echo hi\n'                   > "$SAMPLES/Dockerfile"
printf '# Title\n\nSome *text*.\n'                             > "$SAMPLES/sample.md"
printf '\\documentclass{article}\n\\begin{document}\nhi\n\\end{document}\n' > "$SAMPLES/sample.tex"
printf 'GET https://example.com/api\n'                         > "$SAMPLES/sample.http"

# -- LilyPond samples -------------------------------------------------------
# FOUR files, not one, because the flymake backend has four separable ways to
# be wrong and section (f) of verify.el runs a real lilypond over each:
#
#   ly-clean    valid, and must produce NOTHING -- a backend that invents
#               diagnostics is worse than no backend
#   ly-warn     NO \version, which is the case that made this port necessary:
#               2.26 emits "file.ly:1: warning: ..." with NO COLUMN, and a
#               pattern requiring one silently drops every warning
#   ly-error    an unknown command, which DOES carry a column (line 2, col 11)
#   ly-include  a RELATIVE \include. The backend compiles a temp copy, so
#               without `-I <source dir>' this file fails to find sub/inc.ily
#               and cascades into three errors that are not in it at all
#
# sample.ly / sample.ily are the language table's rows (major mode only); the
# ly-* four are section (f)'s, and each runs a real lilypond.
printf '\\version "2.26.0"\n{ c8 d8 e8 f8 }\n'                 > "$SAMPLES/sample.ly"
printf 'notesB = { g8 a8 }\n'                                  > "$SAMPLES/sample.ily"
printf '\\version "2.26.0"\n{ c4 d4 e4 f4 }\n'                 > "$SAMPLES/ly-clean.ly"
printf '{ c4 d4 e4 f4 }\n'                                     > "$SAMPLES/ly-warn.ly"
printf '\\version "2.26.0"\n{ c4 d4 \\nosuchcommand e4 }\n'    > "$SAMPLES/ly-error.ly"
printf 'notesA = { c4 d4 }\n'                                  > "$SAMPLES/ly-inc.ily"
printf '\\version "2.26.0"\n\\include "ly-inc.ily"\n{ \\notesA }\n' > "$SAMPLES/ly-include.ly"

# The daemon inherits these; passing them through the environment avoids
# quoting elisp inside shell inside emacsclient --eval.
export EMACS_VANILLA_VERIFY_OUT="$REPORT"
export EMACS_VANILLA_VERIFY_SAMPLES="$SAMPLES"

"$EMACSCLIENT" -s "$SOCKET" --eval '(kill-emacs)' >/dev/null 2>&1
"$EMACS_OUT/bin/emacs" --init-directory="$CONFIG_DIR" --fg-daemon="$SOCKET" \
  >"$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!

READY=0
for _ in $(seq 1 120); do
  if "$EMACSCLIENT" -s "$SOCKET" --eval t >/dev/null 2>&1; then READY=1; break; fi
  sleep 1
done

if [ "$READY" -ne 1 ]; then
  fail "daemon did not come up in 120s"
  echo "---- daemon log ----"
  tail -40 "$DAEMON_LOG"
  printf '\n%d failure(s)\n' "$FAILURES"
  exit 1
fi
pass "daemon up on socket $SOCKET"

# ---------------------------------------------------------------------------
say "4. in-daemon assertions"
# ---------------------------------------------------------------------------
"$EMACSCLIENT" -s "$SOCKET" \
  --eval "(progn (load \"$SCRIPT_DIR/verify.el\" nil t) (my/verify-run) nil)" \
  >/dev/null 2>&1

if [ ! -f "$REPORT" ]; then
  fail "the in-daemon gate wrote no report -- it errored before finishing"
  echo "---- daemon log ----"
  tail -40 "$DAEMON_LOG"
else
  cat "$REPORT"
  if grep -q '^=== PASS' "$REPORT"; then
    pass "in-daemon assertions"
  else
    fail "in-daemon assertions"
  fi
fi

# ---------------------------------------------------------------------------
if [ "$FAILURES" -eq 0 ]; then
  printf '\n\033[1mGATE PASS\033[0m\n'
  exit 0
fi
printf '\n\033[1mGATE FAIL: %d stage(s)\033[0m\n' "$FAILURES"
exit 1
