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
USER_NAME=${EMACS_VANILLA_VERIFY_USER:-gfoster}

# The nix system double, obtained WITHOUT an impure evaluation.
#
# This line was `nix eval --raw --impure --expr builtins.currentSystem`, and
# it was the only --impure in the entire repo: an audit found no
# builtins.getEnv, no <nixpkgs> search-path lookup, no currentTime, and every
# flake input pinned by rev. Benign in effect, but a lone exception is how
# the habit comes back, and nothing here needs impurity to know what machine
# it is on.
#
# `nix config show system` reports the same string out of nix's own settings
# -- that setting is where builtins.currentSystem gets its value -- and it is
# the double nix will actually BUILD for, which is the question this variable
# is asking. It is a settings query, not an evaluation, so there is no
# purity to violate.
#
# A `uname -s`/`uname -m` mapping was the obvious alternative and is worse on
# both counts that matter here. It needs a translation table (Darwin reports
# `arm64` where the nix double says `aarch64`, and `Darwin` where the double
# says `darwin`), and it describes the CPU rather than the nix installation:
# an x86_64 nix on Apple Silicon would be told aarch64-darwin and then fail
# to build it, which is precisely the aarch64-darwin/x86_64-darwin confusion
# this repo already carries a pinned nixpkgs for.
#
# EMACS_VANILLA_VERIFY_SYSTEM overrides it, matching the USER_NAME
# convention above -- that is the `--system` flag, spelled the way the rest
# of this file spells its knobs. An empty result is FATAL rather than
# defaulted: falling back to x86_64-linux would have a Mac silently gate a
# configuration that is not its own.
SYSTEM=${EMACS_VANILLA_VERIFY_SYSTEM:-$(nix config show system 2>/dev/null)}
if [ -z "$SYSTEM" ]; then
  # No backticks in these strings. They would only be prose formatting, but a
  # backtick inside single quotes reads as an attempted command substitution
  # (SC2016) and the whole gate exits 1 over punctuation in an error message.
  # Quoting the command names instead costs nothing and leaves nothing to
  # suppress -- better than a disable directive for a finding that exists
  # solely because of a decorative character.
  #
  # Note also that a comment line may not BEGIN with the word shellcheck
  # after the hash: that is the directive syntax, and prose starting that way
  # is parsed as a malformed directive (SC1072/SC1073, both errors). An
  # earlier draft of this very comment did exactly that.
  printf 'FATAL: could not determine the nix system double.\n' >&2
  printf "       'nix config show system' returned nothing (nix < 2.20 spells\n" >&2
  printf "       it 'nix show-config system'). Override it explicitly:\n" >&2
  printf '       EMACS_VANILLA_VERIFY_SYSTEM=x86_64-linux bash %s\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi

FAILURES=0
SOCKET=emacs-vanilla-verify
WORK=$(mktemp -d)
REPORT="$WORK/report.txt"
DAEMON_LOG="$WORK/daemon.log"
DAEMON_PID=""

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

# `cleanup` is invoked by `trap cleanup EXIT` on the line below. Shellcheck
# cannot prove reachability through `trap` in any version, and its own message
# says what to do about it: "Check usage (or ignore if invoked indirectly)".
# This is that case -- the documented remedy for indirect invocation, not a
# linter being wrong and not a finding being dodged.
#
# The alternative that needs no suppression is inlining this body into the
# trap string. Rejected: five legible lines become one quoted line with `$`
# escaping, in the file whose entire job is to be auditable. Blanket
# `--severity=warning` was also rejected -- silencing a whole class everywhere
# to excuse one known-good site is strictly worse than one scoped directive.
#
# BOTH codes, because shellcheck renumbered this finding: SC2329 ("function
# never invoked") in 0.11, SC2317 ("command appears to be unreachable") in
# earlier releases, where it lands on every line of the body rather than on
# the function. Naming only the newer code passed locally on 0.11.0 and failed
# CI on an older one. Info severity is enough to make shellcheck exit 1.
# shellcheck disable=SC2317,SC2329
cleanup() {
  if [ -n "$DAEMON_PID" ]; then
    "$EMACSCLIENT" -s "$SOCKET" --eval '(kill-emacs)' >/dev/null 2>&1
    wait "$DAEMON_PID" 2>/dev/null
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# THE LINTERS ARE PINNED, NOT DISCOVERED.
#
# This used to prefer whatever `command -v` found and fall back to
# `nix run nixpkgs#<tool>`. That fallback resolves through the RUNNER's flake
# registry rather than through this flake's own pinned nixpkgs input, so the
# same gate ran different tool versions here and in CI.
#
# It went red on PR #21. shellcheck renumbered one finding -- SC2329 in 0.11,
# SC2317 in earlier releases (see the disable directive above) -- this file
# named only SC2329, passed locally on 0.11.0 out of the profile, and failed
# CI on an older one out of the registry. Naming both codes fixed that
# instance and not the class.
#
# Every linter now comes out of packages.<system>.lint-tools, a symlinkJoin
# built from this flake's nixpkgs (see lib/lint-tools.nix). ci.yml's lint job
# resolves the same derivation. Local and CI therefore agree by construction
# instead of by both happening to have the same tool installed.
#
# PATH is deliberately NOT consulted, not even as a preference: a PATH
# preference IS the skew, and a fallback that can win is not a pin. There is
# a flake check guarding the regression -- `lint-tools-pinned` in flake.nix.
LINT_TOOLS=""

# Resolve a linter from the pinned set, and from nothing else. A linter that
# cannot be found is a FAILURE, never a skip -- silently skipping is exactly
# how a gate ends up green while checking nothing.
resolve_linter() {
  local tool=$1
  if [ -n "$LINT_TOOLS" ] && [ -x "$LINT_TOOLS/bin/$tool" ]; then
    printf '%s' "$LINT_TOOLS/bin/$tool"
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
    fail "$tool is not in the pinned lint set (nix build $REPO#lint-tools)"
    return
  fi
  # Report WHICH binary and WHICH version, always. Before the pin this was
  # diagnosis: the one line of log that would have identified the skew above
  # instead of a dig through 80,000. It is now PROOF -- the path is a store
  # path out of this flake's nixpkgs, so the version printed here is the
  # version CI runs, and a change in it means the lock moved and nothing
  # else. Ambient PATH cannot alter either field.
  #
  # The path is DEREFERENCED through the lint-tools symlink, because the
  # derivation name carries the version. That is not cosmetic: statix has no
  # --version flag whatsoever (`statix --version` is an argument error), so
  # for that one tool the store path is the only evidence of which build ran.
  local ver status=0 real
  real=$(readlink -f "$resolved")
  ver=$("$resolved" --version 2>/dev/null | head -2 | tr '\n' ' ')
  "$resolved" "$@" || status=$?
  printf '        via %s [%s]\n' "$real" "${ver:-no --version flag; version is in the path}"
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
say "1. nix lint (exit codes, not stdout; versions pinned, not discovered)"
# ---------------------------------------------------------------------------
cd "$REPO" || exit 1

# Build the pinned set first -- every linter below is resolved out of it, so
# a failure here is reported once rather than four times.
LINT_TOOLS=$(nix build "$REPO#lint-tools" --no-link --print-out-paths) || LINT_TOOLS=""
if [ -n "$LINT_TOOLS" ]; then
  pass "pinned lint set: $LINT_TOOLS"
else
  fail "could not build $REPO#lint-tools -- every linter below will fail"
fi

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
