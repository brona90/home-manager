# Guards: the Windows half of this machine gets what the flake says it gets.
#
# Claude Code runs natively on Windows here, against the same repositories,
# reading C:\Users\<winuser>\.claude\settings.json -- a file home-manager cannot
# reach and no check had ever looked at. modules/windows-bridge.nix now merges a
# managed fragment into it. These guards are what keep that fragment honest,
# because every failure mode it has is silent: the Windows side simply stops
# doing something the WSL side still does, and only a human comparing two files
# by hand would notice.
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
#   winTargets       -- every `target' in config.my.windowsBridge.files, as a
#                       list of profile-relative paths.
#   lib              -- nixpkgs.lib.
#
# SHOWN FAILING. checks/dev-shell.nix already records what happens otherwise:
# the first cut of `devshell-stays-light' inspected the wrong thing, and a
# deliberate re-introduction of the regression sailed straight past it. A guard
# only ever observed passing has not been shown to guard anything -- and that is
# the specific hazard here, because `windows-bridge-attribution' was itself
# written in response to a guard that was green and meant nothing
# (checks/claude-settings.nix, which had only ever seen the WSL settings.json).
# Repeating that shape without testing it would have been the same bug twice.
#
# Each invariant below was therefore broken on purpose, the guard built alone,
# and its exit code read. All six were caught; none was missed:
#
#   MUTATION                                            GUARD THAT CAUGHT IT
#   windowsProfileBin rendered as a /nix/store path      no-store-paths      (1)
#   kg-capture-hook-win's windowsProfileBin set to null  claude-kg-hooks     (1)
#   .claude/CLAUDE.md target renamed away                claude-surfaces     (1)
#   .claude/skills + agents targets renamed away         claude-surfaces     (1)
#   .claude/statusline-command.sh target renamed away    claude-surfaces     (1)
#   attribution replaced with a Co-Authored-By trailer   attribution         (1)
#
# Re-run one by editing the named source, then:
#   nix build .#checks.x86_64-linux.<guard> --no-link; echo $?
# Read the exit code. Do not grep the output for a success string -- that is the
# failure mode modules/emacs/vanilla/verify.sh names in its own header.
{
  lib,
  pkgs,
  winSettingsText,
  winTargets,
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

  # No /nix/store path may reach the Windows fragment.
  #
  # This is the invariant that makes generating the Windows hooks safe at all.
  # The WSL settings.json is rewritten from scratch on every switch, so a store
  # path in it is refreshed the moment it changes. The Windows one is MERGED:
  # activation writes the managed keys and leaves the file otherwise as it found
  # it, and nothing revisits it in between. A store path recorded there goes on
  # naming a generation that garbage collection is free to remove, and the
  # failure is silent -- the hook stops running on Windows while continuing to
  # work in WSL, which is the exact shape of drift this bridge exists to stop.
  #
  # Hence windowsProfileBin taking a NAME under ~/.nix-profile/bin instead of a
  # command. This guard is what keeps that from being merely a convention.
  windows-bridge-no-store-paths =
    pkgs.runCommand "windows-bridge-no-store-paths" {
      settings = winSettingsText;
      passAsFile = ["settings"];
    } ''
      if grep -o '/nix/store/[^"]*' "$settingsPath"; then
        echo 'GUARD: the Windows settings.json fragment names the /nix/store path(s) above.'
        echo '       That file is merged, not regenerated, so the path is never refreshed:'
        echo '       it dangles as soon as the store path changes and the hook stops running,'
        echo '       silently, on the Windows side only.'
        echo '       Name the wrapper through ~/.nix-profile/bin instead (windowsProfileBin).'
        exit 1
      fi
      touch $out
    '';

  # The knowledge-graph hooks reach Windows FROM THE FLAKE.
  #
  # Before this, C:\Users\<winuser>\.claude\settings.json carried three
  # hand-written hook entries -- kg-session-start-hook, kg-prompt-recall-hook and
  # kg-capture-hook-win -- that appeared nowhere in this repository. The WSL half
  # got its hooks from modules/claude-kg; the Windows half got them from whoever
  # last edited that file. Rebuilding the WSL instance reproduced one half and
  # not the other, and nothing anywhere said so.
  #
  # kg-capture-hook-win is the sharpest case: modules/claude-kg builds it purely
  # for the Windows caller, so its only consumer in the world was that
  # hand-written line -- a package the flake built for a reference the flake could
  # not see. Asserting all three keeps the generated fragment from quietly losing
  # them the way the attribution block was lost.
  windows-bridge-claude-kg-hooks =
    pkgs.runCommand "windows-bridge-claude-kg-hooks" {
      nativeBuildInputs = [pkgs.jq];
      settings = winSettingsText;
      passAsFile = ["settings"];
    } ''
      for want in \
        SessionStart:kg-session-start-hook \
        UserPromptSubmit:kg-prompt-recall-hook \
        SessionEnd:kg-capture-hook-win; do
        event=''${want%%:*}
        bin=''${want##*:}
        jq -e --arg e "$event" --arg b "$bin" \
          '[.hooks[$e][]?.hooks[]?.command] | any(endswith("/" + $b))' \
          "$settingsPath" > /dev/null \
          || { echo "GUARD: the Windows settings.json fragment runs no $bin on $event."; \
               echo '       Those three hooks lived only in the Windows file, by hand, until'; \
               echo '       they were generated here. Dropping one means a rebuilt machine'; \
               echo '       runs the knowledge graph on the WSL side only, and says nothing.'; \
               exit 1; }
      done
      touch $out
    '';

  # Each managed Claude surface still crosses to Windows AT ALL.
  #
  # The other guards in this file check that what crosses is correct. This one
  # checks that it crosses, which is the failure that actually happened: the
  # Windows skills, subagents and CLAUDE.md were not wrong so much as unclaimed,
  # copied by hand in August and never revisited, and no check could have noticed
  # because no check knew they were supposed to exist. `nix flake check' cannot
  # read C:\Users, so this asserts against the set of targets the flake claims --
  # the closest thing to that file tree that is knowable at eval time.
  #
  # Deliberately a presence test and not a content test. Content is already
  # settled: both sides read the same bundle in modules/claude-skills and the
  # same claudeMdSections join, so a guard comparing them would compare a value
  # to itself and could only ever pass. What is genuinely losable is the
  # CONTRIBUTION -- a refactor that drops `my.windowsBridge.files' from a module
  # leaves every other check green and silently returns the Windows side to being
  # maintained by hand.
  windows-bridge-claude-surfaces =
    pkgs.runCommand "windows-bridge-claude-surfaces" {
      targets = lib.concatStringsSep "\n" winTargets;
      passAsFile = ["targets"];
    } ''
      need() {
        grep -qE "$1" "$targetsPath" && return 0
        echo "GUARD: no Windows-side target matches $1"
        echo "       $2"
        echo '       Claude Code runs natively on Windows here and reads that path.'
        echo '       Dropping the bridge entry does not break anything visibly; it'
        echo '       just returns the file to being maintained by hand, which is how'
        echo '       the stale skills and the missing attribution block happened.'
        exit 1
      }
      need '^\.claude/CLAUDE\.md$' 'The user-scope directives, including the knowledge-graph write-side directive.'
      need '^\.claude/statusline-command\.sh$' 'The statusline named by the settings fragment; without it the key points at nothing.'
      need '^\.claude/skills/' 'The skill bundle from modules/claude-skills.'
      need '^\.claude/agents/' 'The subagent definitions from modules/claude-skills.'
      touch $out
    '';
}
