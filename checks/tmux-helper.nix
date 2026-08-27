# Builds of the Go tmux helper: it compiles, and `go vet` is clean across every
# package in it.
#
# These are ordinary builds rather than regression guards, and they are the only
# entries in checks/ defined on EVERY system -- a compiled binary is exactly the
# thing that breaks on one platform and not another.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs -- `pkgsFor system`: this flake's nixpkgs for the system being
#           checked, overlays and config already applied.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{pkgs}: {
  tmux-helper-build = pkgs.callPackage ../modules/tmux-helper/package.nix {};

  # Runs go vet across the helper sources. buildGoModule's checkPhase
  # already runs go test, but vet only fires for packages with _test.go
  # files; this check exercises every package regardless.
  tmux-helper-vet =
    pkgs.runCommand "tmux-helper-vet" {
      nativeBuildInputs = [pkgs.go];
    } ''
      export HOME=$TMPDIR
      export GOCACHE=$TMPDIR/go-build
      # Match package.nix: helper is built CGO_ENABLED=0, so vet (which
      # otherwise resolves runtime/cgo and demands gcc) must match.
      export CGO_ENABLED=0
      cp -r ${../modules/tmux-helper/src} src
      chmod -R u+w src
      cd src
      go vet ./...
      touch $out
    '';
}
