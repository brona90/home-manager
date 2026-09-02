# Guards on the embedder and on the hooks that depend on it.
#
# Every assertion here encodes a failure that already happened on this estate
# and cost real time to find. None of them is a style rule.
#
# NOTE for anyone editing these builders: nixpkgs' stdenv runs them under
# `set -eu -o pipefail`. That means `cmd | grep -q X && fail` ABORTS THE BUILD
# on the healthy path, because the short-circuited `&&` list exits non-zero,
# and that a command substitution whose pipeline contains a non-matching grep
# does the same. Every such spot below is written as `if ...; then fail; fi`
# or ends in `|| true` on purpose.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs       -- `pkgsFor system` for the system being checked.
#   ollamaUnit -- the rendered systemd user unit for the Ollama server, taken
#                 from the BUILT home configuration rather than from module
#                 source, so the guard sees what activation would write.
#   kgHook     -- the built kg-prompt-recall-hook package, likewise, so the
#                 guard reads the script that actually gets installed.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{
  pkgs,
  ollamaUnit,
  kgHook,
}: let
  unitEnv = builtins.concatStringsSep "\n" (ollamaUnit.Service.Environment or []);
in {
  # The vendor's hand-rolled /etc/systemd/system/ollama.service froze a snapshot
  # of an interactive shell's PATH into the unit. Measured on this box before
  # the module replaced it: 65 entries, 29 of them already dead -- the entire
  # mise install tree, /Docker/host/bin, and /mnt/c/Users/brona/.local/share/
  # mise/bin. Each /mnt/c entry is a 9P round trip per lookup, and `ollama serve`
  # execs nothing but its own runners, so none of it was ever needed.
  ollama-unit-path-is-store-only =
    pkgs.runCommand "ollama-unit-path-is-store-only" {
      inherit unitEnv;
      passAsFile = ["unitEnv"];
    } ''
      path_line=$(grep '^PATH=' "$unitEnvPath" || true)
      if [ -z "$path_line" ]; then
        echo 'GUARD: the ollama unit sets no explicit PATH.'
        echo '       An unset PATH is how the vendor unit inherited a 65-entry'
        echo '       interactive one in the first place. Set it explicitly.'
        exit 1
      fi
      bad=$(printf '%s\n' "''${path_line#PATH=}" | tr ':' '\n' \
        | grep -v '^/nix/store/' | grep -v '^$' || true)
      if [ -n "$bad" ]; then
        echo 'GUARD: the ollama unit PATH contains non-store entries:'
        printf '         %s\n' $bad
        echo '       The unit this replaced baked an interactive PATH with 29'
        echo '       dead entries. `ollama serve` execs nothing but its own'
        echo '       runners; this PATH must stay store-only.'
        exit 1
      fi
      touch $out
    '';

  # The driver library path is the one thing that must legitimately point
  # OUTSIDE the store, and it must be there or the GPU is silently unused.
  # Measured on this box with a per-request num_gpu:0 against the live server:
  # qwen2.5:7b runs at 83.4 tok/s on the GPU and 0.3 tok/s on the CPU. That
  # 278x is the difference between the SessionEnd capture completing and
  # blowing capture_local.py's 300s read timeout every single time.
  ollama-unit-exports-driver-libs =
    pkgs.runCommand "ollama-unit-exports-driver-libs" {
      inherit unitEnv;
      passAsFile = ["unitEnv"];
    } ''
      if ! grep -q '^LD_LIBRARY_PATH=..*' "$unitEnvPath"; then
        echo 'GUARD: the ollama unit does not export LD_LIBRARY_PATH.'
        echo '       The bundled CUDA runners reach the host libcuda.so.1 only'
        echo '       through it -- it is deliberately not in the store, because'
        echo '       the userspace driver must match the kernel one. Without'
        echo '       it every model silently falls back to the CPU.'
        exit 1
      fi
      touch $out
    '';

  # The recall hook must decide whether the embedder is alive BEFORE it spends
  # anything, and must say so when it is not.
  #
  # What this replaced: `kg recall ... 2>/dev/null | jq ... || true` followed by
  # `if [ -z "$digest" ]; then exit 0`. Three silencers on one line -- stderr
  # discarded, the exit code discarded twice over (by the pipeline, which
  # reports jq's status, and again by `|| true`), and an empty result treated as
  # success. Measured against an unreachable embedder: 123.5s of blocking, zero
  # bytes, exit 0 -- byte-identical to "nothing relevant found", and more than
  # the hook's entire 60s Claude Code budget.
  kg-recall-hook-probes-before-spending = pkgs.runCommand "kg-recall-hook-probes-before-spending" {} ''
    hook=${kgHook}/bin/kg-prompt-recall-hook

    # Grep the CODE, not the prose. Every check below runs against a
    # comment-stripped copy, because the first version of this guard did not
    # and was trivially satisfiable by a comment: deleting the real
    # `curl --connect-timeout ... --max-time ...` left the sentence
    # "# --connect-timeout AND --max-time: a black-holed address never
    # completes" behind, the grep matched it, and the guard passed on a hook
    # with an unbounded probe. Mutation-testing this guard is what found that;
    # a guard that reads its own documentation asserts nothing.
    grep -v '^[[:space:]]*#' "$hook" > code.sh || true

    fail() {
      echo "GUARD: $1"
      shift
      for line in "$@"; do echo "       $line"; done
      exit 1
    }

    # The anchor is `kg recall "` -- WITH the double quote -- and that detail
    # is load-bearing. A bare `kg recall` also matches this hook's own
    # diagnostic, printf 'claude-kg: recall FAILED (kg recall exited %s)...',
    # whose arguments contain `head -c 300 ... | tr`. Anchoring without the
    # quote made this guard fail on a CLEAN tree by "finding" that pipe, which
    # in turn made two of its mutation tests look detected when they were only
    # hitting the same false positive. Found by mutation-testing the guard
    # itself; do not loosen it back.
    #
    # The recall STATEMENT is that line plus the two before it: the call is
    # wrapped across lines by `timeout N \`, so a single-line grep would see
    # only half of it. `||` is squashed to _OR_ first so the shell's
    # or-operator is never mistaken for a pipe by check 4.
    stmt=$(grep -B2 'kg recall "' code.sh | tr '\n' ' ' | sed 's/||/ _OR_ /g' || true)

    # 1. A bounded probe must exist, and must run BEFORE any recall.
    probe_line=$(grep -n 'api/tags' code.sh | head -1 | cut -d: -f1 || true)
    recall_line=$(grep -n 'kg recall "' code.sh | head -1 | cut -d: -f1 || true)
    if [ -z "$probe_line" ]; then
      fail 'kg-prompt-recall-hook never probes the embedder.' \
        'Without a probe an absent backend costs 123s of silence per prompt.'
    fi
    if [ -z "$recall_line" ]; then
      fail 'kg-prompt-recall-hook no longer calls `kg recall`.'
    fi
    if [ "$probe_line" -ge "$recall_line" ]; then
      fail "the probe (line $probe_line) does not precede the recall (line $recall_line)." \
        'Probing after the expensive call defeats the entire purpose.'
    fi

    # 2. An unbounded probe is not a probe. A black-holed address never
    #    completes a handshake; an overloaded one connects and then stalls.
    #    Both ends must be capped.
    if ! grep -q -- '--connect-timeout' code.sh; then
      fail 'the embedder probe has no --connect-timeout.'
    fi
    if ! grep -q -- '--max-time' code.sh; then
      fail 'the embedder probe has no --max-time.'
    fi

    # 3. The recall itself must be bounded too, for the one case the probe
    #    cannot catch: a server that accepts the connection and then hangs.
    if ! printf '%s' "$stmt" | grep -q 'timeout [0-9]'; then
      fail '`kg recall` is not wrapped in a `timeout`.' \
        'The probe cannot catch a backend that answers and then stalls.'
    fi

    # 4. The exit code must come from `kg recall` itself, never from the tail
    #    of a pipeline. `kg recall ... | jq` reports JQ's success and throws
    #    the recall failure away; that exact defect is what made this hook
    #    unable to tell a dead backend from an empty graph.
    if printf '%s' "$stmt" | grep -q '|'; then
      fail '`kg recall` pipes into another command.' \
        'A pipeline reports the exit status of its LAST member, so the' \
        'recall failure is silently discarded. Capture to a variable with' \
        '`|| rc=$?` and parse it in a separate step.'
    fi

    # 5. ...and it must not be silenced by hand either.
    if printf '%s' "$stmt" | grep -q '2>/dev/null'; then
      fail 'the `kg recall` call sends stderr to /dev/null.' \
        'Its stderr is the only evidence of WHY a recall failed.'
    fi
    if printf '%s' "$stmt" | grep -qE '_OR_ +true'; then
      fail 'the `kg recall` call is swallowed by `|| true`.' \
        'That converts every backend failure into a successful empty result.'
    fi

    # 6. The unreachable branch has to tell somebody. On a UserPromptSubmit
    #    hook stdout is injected into the MODEL's context, not shown to the
    #    user; stderr plus a non-zero exit is what Claude Code surfaces.
    if ! grep -A3 'UNREACHABLE' code.sh | grep -q '>&2'; then
      fail 'the unreachable branch does not report on stderr.' \
        'stdout goes to the model, not to the user who needs to fix it.'
    fi

    # 7. ...but it must never BLOCK the prompt. Exit code 2 is Claude Code's
    #    "reject this prompt" signal for UserPromptSubmit. A missing embedder
    #    must degrade the turn, never cancel the user's work.
    if grep -qE '^[[:space:]]*exit 2[[:space:]]*$' code.sh; then
      fail 'the hook can exit 2, which BLOCKS the user prompt.' \
        'Use exit 1: non-blocking, and its stderr is still surfaced.'
    fi

    touch $out
  '';
}
