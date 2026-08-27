# Guard: what the docker terminal is allowed to mount into a container.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs -- `pkgsFor system` for the system being checked.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{pkgs}: {
  # The docker terminal must never bind-mount ~/.ssh (it holds the
  # sops-decrypted private key); SSH is agent-forwarding only.
  docker-terminal-no-ssh-mount = pkgs.runCommand "docker-terminal-no-ssh-mount" {} ''
    if grep -q '\$HOME/\.ssh:' ${../modules/docker-terminal.nix} ${../lib/docker-test-app.nix}; then
      echo 'GUARD: ~/.ssh must not be bind-mounted into containers'
      exit 1
    fi
    touch $out
  '';
}
