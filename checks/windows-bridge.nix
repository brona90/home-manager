# Guard: the Windows half of this machine obeys the same attribution rule as the
# WSL half.
#
# checks/claude-settings.nix has asserted since it was written that
# ~/.claude/settings.json carries an empty `attribution' block, and it has always
# passed -- because the only settings.json it can see is the WSL one. Claude Code
# also runs NATIVELY ON WINDOWS here, against the same repositories, reading
# C:\Users\<winuser>\.claude\settings.json, which home-manager could not reach
# and no check had ever looked at. That file drifted: it lost the block, and
# commits and PRs made from a Windows session carried Co-Authored-By trailers and
# "Generated with Claude Code" footers that the identical work done from WSL did
# not. The rule was never relaxed and the guard never failed; the file simply
# was not in scope. This puts it in scope.
#
# It is a separate assertion rather than an extra line in claude-settings.nix
# because the two files are produced differently: the WSL one is a whole rendered
# settings.json, the Windows one is a managed FRAGMENT that
# modules/windows-bridge.nix merges into a file Claude Code also writes. Both
# ultimately read the same `attribution' definition in modules/claude-code.nix,
# so this guard is what proves the second consumer of that definition still gets
# it -- if the fragment stops carrying the block, the merge silently stops
# enforcing anything and nothing else would notice.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs             -- `pkgsFor system` for the system being checked.
#   winSettingsText  -- the RENDERED text of the managed fragment for the Windows
#                       .claude/settings.json, taken from the evaluated home
#                       configuration
#                       (config.my.windowsBridge.files.claude-settings.text).
#                       Reading the built value rather than grepping
#                       modules/claude-code.nix is the point: the guard sees the
#                       bytes activation would actually merge.
{
  pkgs,
  winSettingsText,
}: {
  windows-bridge-attribution =
    pkgs.runCommand "windows-bridge-attribution" {
      nativeBuildInputs = [pkgs.jq];
      settings = winSettingsText;
      passAsFile = ["settings"];
    } ''
      jq -e '.attribution == {commit: "", pr: ""}' "$settingsPath" >/dev/null \
        || { echo 'GUARD: the Windows settings.json fragment must set attribution to {commit: "", pr: ""}'; \
             echo '       Without it, commits and PRs made from a Windows Claude Code session'; \
             echo '       carry attribution trailers that the same work from WSL does not.'; exit 1; }
      touch $out
    '';
}
