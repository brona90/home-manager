# Hook set handed to git-hooks.nix (see `preCommitFor` in flake.nix).
#
# This lives in its own file, rather than inline in flake.nix, so that
# lib/dev-shell.nix can cheaply hash it with `builtins.hashFile` to decide
# whether the hooks installed in .git/hooks are out of date -- WITHOUT
# evaluating git-hooks.nix, which is ~19s of it (see the measurements in
# lib/dev-shell.nix). Hashing flake.nix instead would be useless: it changes
# on every unrelated edit and would trigger a pointless reinstall each time.
{
  statix.enable = true;
  deadnix.enable = true;
  alejandra.enable = true;
  shellcheck.enable = true;
}
