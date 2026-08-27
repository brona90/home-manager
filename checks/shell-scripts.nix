# Guards on the hand-written shell scripts this flake installs into a clone:
# lib/dev-shell-hook.sh, lib/install-hooks.sh, lib/warm-direnv.sh and
# lib/link-pc-config.sh.
#
# Nothing else looks at them. They are sourced at an interactive prompt or
# exec'd from a git hook, where a mistake shows up as a broken terminal or a
# silent no-op rather than as a build failure -- so they get linted here, where
# nobody is waiting, and grepped here for the one property shellcheck cannot
# express.
#
# What those scripts must DO is guarded in checks/dev-shell.nix; this file is
# about them as scripts.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs -- `pkgsFor system` for the system being checked.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{pkgs}: {
  # The background jobs must stay backgrounded. Closing the
  # inherited descriptors is what makes them detach: direnv hands
  # the .envrc an extra pipe on FD 3 and reads it to EOF, so a child
  # that inherits FD 3 blocks the caller no matter how completely
  # stdin/stdout/stderr are redirected. Measured: 9364ms without
  # this line, 713ms with it. nohup, setsid and double-forking all
  # made no difference, so "it looks detached" is not evidence.
  background-jobs-close-fds = pkgs.runCommand "background-jobs-close-fds" {} ''
    for f in ${../lib/dev-shell-hook.sh} ${../lib/warm-direnv.sh}; do
      grep -q 'exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-' "$f" \
        || { echo "GUARD: $f spawns a background job without closing inherited descriptors."; \
             echo '       FD 3 is direnv'"'"'s capture pipe; leaving it open re-blocks the caller.'; exit 1; }
    done
    touch $out
  '';

  # The shellHook is a hand-written shell script that mkShell will
  # never lint for us, and it runs at an interactive prompt where a
  # syntax error looks like a broken terminal. Lint it here, where
  # nobody is waiting.
  devshell-hook-lint =
    pkgs.runCommand "devshell-hook-lint" {
      nativeBuildInputs = [pkgs.shellcheck];
    } ''
      cp ${../lib/dev-shell-hook.sh} hook.sh
      shellcheck --shell=bash hook.sh
      cp ${../lib/install-hooks.sh} install-hooks.sh
      shellcheck --shell=bash install-hooks.sh
      cp ${../lib/warm-direnv.sh} warm-direnv.sh
      shellcheck --shell=bash warm-direnv.sh
      cp ${../lib/link-pc-config.sh} link-pc-config.sh
      shellcheck --shell=bash link-pc-config.sh

      touch $out
    '';
}
