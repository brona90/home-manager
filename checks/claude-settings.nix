# Guard: what Claude Code is allowed to do from this configuration.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs         -- `pkgsFor system` for the system being checked.
#   settingsText -- the RENDERED text of ~/.claude/settings.json, taken from the
#                   evaluated home configuration
#                   (config.home.file.".claude/settings.json".text). Reading the
#                   built value rather than grepping modules/claude-code.nix is
#                   the point: the guard sees what activation would actually
#                   write, no matter how many modules contributed to it.
{
  pkgs,
  settingsText,
}: {
  # Claude Code must never attribute itself in commits/PRs, and
  # emacs_eval (arbitrary elisp = arbitrary shell) must never be
  # auto-allowed.
  claude-settings-guards =
    pkgs.runCommand "claude-settings-guards" {
      nativeBuildInputs = [pkgs.jq];
      settings = settingsText;
      passAsFile = ["settings"];
    } ''
      jq -e '.attribution == {commit: "", pr: ""}' "$settingsPath" >/dev/null \
        || { echo 'GUARD: settings.json attribution must be {commit: "", pr: ""}'; exit 1; }
      jq -e '(.permissions.allow // []) | index("mcp__emacs__emacs_eval") == null' "$settingsPath" >/dev/null \
        || { echo 'GUARD: mcp__emacs__emacs_eval must not be auto-allowed'; exit 1; }
      touch $out
    '';
}
