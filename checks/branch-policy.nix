# Guard: the specflow branch-policy hook stays worktree-aware AND keeps failing
# closed. Runs the shipped hook against
# modules/claude-specflow/tests/branch-policy-matrix.sh.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs -- `pkgsFor system` for the system being checked.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{pkgs}: {
  # The specflow branch-policy hook must stay worktree-aware AND
  # keep failing closed.
  #
  # The hook decides whether a Bash tool call may commit or push,
  # from nothing but the command string, before that command runs.
  # Which directory a commit lands in therefore has to be inferred,
  # and that inference has now been wrong in both directions.
  #
  # It shipped reading the branch with a bare `git rev-parse` in
  # the hook's OWN cwd -- the main checkout, normally sitting on
  # master -- so every commit made in a worktree was blocked as if
  # it were a commit on master. The first fix for that (PR #6,
  # closed unmerged) resolved one directory and fell back to
  # `|| true`, which turned every parse miss into a silent ALLOW:
  # it let `cd <worktree> && cd <main> && git commit` and
  # `cd <nonexistent> && git commit` put a commit on master.
  #
  # A guard that only checked the worktree case would have passed
  # on that second version. modules/claude-specflow/tests runs both
  # directions -- 43 cases, and its own comment lists the eight
  # deliberate breakages it was confirmed to catch, because a
  # matrix nobody has ever seen fail proves nothing.
  branch-policy-hook =
    pkgs.runCommand "branch-policy-hook" {
      nativeBuildInputs = [pkgs.bash pkgs.git pkgs.jq];
    } ''
      export HOME="$TMPDIR"
      bash ${../modules/claude-specflow/tests/branch-policy-matrix.sh} \
        ${../modules/claude-specflow/templates/specflow/hooks/branch-policy.sh}

      touch $out
    '';
}
