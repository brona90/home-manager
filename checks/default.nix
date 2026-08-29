# The `nix flake check` guard set: one file per concern, merged here.
#
# flake.nix's `checks` output is nothing but `forAllSystems (system: import
# ./checks {...})`. That is the whole reason this directory exists: the guards
# used to be a single 400-line attrset in flake.nix, so every branch that added
# or touched one edited the same lines and conflicted with every other branch
# that did. Two guards in two files now merge cleanly.
#
# ADDING A GUARD: put it in the file for its concern, or add a new file and one
# `// import ./<file>.nix {...}` line below. Guard ATTRIBUTE NAMES are
# load-bearing -- `nix build .#checks.x86_64-linux.<name>` is how a single guard
# is run by hand, and README.md, .github/SETUP.md and
# modules/claude-skills/skills/nix-home-manager/SKILL.md all name them in prose.
# Renaming one is a documentation change as well as a code change.
#
# INPUTS. Everything below is passed explicitly from flake.nix's top-level
# `let`; no file in this directory can see that scope, so this list is the
# complete interface between the flake and its guards.
#
#   lib           -- nixpkgs.lib.
#   pkgs          -- `pkgsFor system`: this flake's nixpkgs for the system being
#                    checked, overlays and config already applied.
#   system        -- the system double being checked. Used only for the
#                    x86_64-linux gate below.
#   homeConfigs   -- the whole homeConfigurations attrset, keyed
#                    "<username>@<system>". Read for the rendered
#                    .claude/settings.json (both the WSL file and the managed
#                    fragment for the Windows one), so the guards see what
#                    activation would write rather than what a module source says.
#   userForSystem -- system -> the config.nix user head-picked for that system
#                    (or null); paired with homeConfigs to build the key above.
#   devShellFor   -- system -> lib/dev-shell.nix's output set.
#
# The last two are passed as FUNCTIONS rather than as already-applied values on
# purpose. `devShellFor` reaches git-hooks.lib.<system>, which is built from the
# followed (channel) nixpkgs and throws for the dropped x86_64-darwin platform;
# keeping it unapplied until inside the x86_64-linux branch means it is never
# forced anywhere it would throw. userForSystem follows it for symmetry, and
# because it returns null on a system with no configured user.
{
  lib,
  pkgs,
  system,
  homeConfigs,
  userForSystem,
  devShellFor,
}:
# Ordinary builds, every system.
import ./tmux-helper.nix {inherit pkgs;}
# Regression guards for resolved review findings. Pure-eval + trivial
# builds; defined once on x86_64-linux (the guarded content is identical
# across systems). `nix flake check` fails if any future change
# reintroduces these.
// lib.optionalAttrs (system == "x86_64-linux") (
  let
    user = userForSystem system;
    settingsText =
      homeConfigs."${user.username}@${system}".config.home.file.".claude/settings.json".text;
    # The Windows-side counterpart: the managed fragment
    # modules/windows-bridge.nix merges into C:\Users\<winuser>\.claude\settings.json.
    # Contributed unconditionally by modules/claude-code.nix, so it is present on
    # every configuration and readable here whether or not the bridge is enabled
    # for this host.
    winSettingsText =
      homeConfigs."${user.username}@${system}".config.my.windowsBridge.files.claude-settings.text;
    dev = devShellFor system;
  in
    import ./claude-settings.nix {inherit pkgs settingsText;}
    // import ./windows-bridge.nix {inherit pkgs winSettingsText;}
    // import ./docker-terminal.nix {inherit pkgs;}
    // import ./emacs-gate.nix {inherit pkgs;}
    // import ./lint-tools.nix {inherit pkgs;}
    // import ./dev-shell.nix {inherit pkgs dev;}
    // import ./shell-scripts.nix {inherit pkgs;}
    // import ./branch-policy.nix {inherit pkgs;}
)
