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
#   homeWriteGuard   -- the built home-root guard package, the same derivation
#                       modules/claude-code.nix puts in home.packages, so that
#                       "is it installed" is an identity comparison rather than
#                       a search for a name.
#   homePackages     -- config.home.packages, for the same comparison.
{
  lib,
  pkgs,
  winSettingsText,
  winTargets,
  homeWriteGuard,
  homePackages,
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

  # THE MUTATION MATRIX FOR THE TWO GUARDS BELOW, and for the two they lean on.
  # Eight cases, eight caught, none missed, and every case restored from a
  # pristine copy rather than with git, so the worktree's index was never
  # touched. The restore is a step with its own evidence -- a sha256 over all
  # four files, compared before and after each case -- because "restore" written
  # as a trailing clause is how a mutation gets left in a worktree for somebody
  # else to find and read as real config.
  #
  #   claude-home-guard-decides
  #     the separator conversion written unquoted again
  #     is_home_root forgetting the Windows profile shape
  #     the UNC case removed
  #     is_home_root refusing everything          <- the allow rows, in reverse
  #   windows-bridge-home-guard-crosses
  #     PreToolUse ceasing to cross
  #     PostToolUse ceasing to cross
  #   windows-bridge-no-store-paths
  #     the crossing named by store path instead of through the profile
  #   windows-bridge-profile-bin-installed
  #     the guard dropped from home.packages
  #
  # The fourth case is the one worth keeping. A matrix of refusals can be
  # satisfied by a guard that refuses everything, and would then be green while
  # blocking every write this configuration makes. Testing only the direction
  # you are afraid of is how a forbid-only check comes to pass vacuously.
  #
  # To re-run: mutate one anchor, build that check, expect a non-zero exit, put
  # the file back, and confirm the digest matches before moving on.

  # The binary a Windows hook names is one the flake actually installs.
  #
  # windows-bridge-no-store-paths forces every crossed command to be named
  # through ~/.nix-profile/bin, because a store path in a merged file dangles.
  # That trade is only sound if the profile really carries the name: a hook
  # pointing at ~/.nix-profile/bin/claude-home-guard when nothing puts
  # claude-home-guard in the profile is not a dangling path, it is a command not
  # found -- which Claude Code reports, if at all, on the Windows side only.
  #
  # This is the statusline-command.sh failure with the arrow reversed. There the
  # settings key named a script the flake did not install; here the settings key
  # names a BINARY the flake might not install, and the WSL side would go on
  # working throughout because it invokes the same program by store path.
  #
  # Compared by identity at eval time rather than by looking for a file: asking
  # whether this exact derivation is in home.packages is a question with an
  # exact answer, where searching a built profile for a name would pass on any
  # other package that happened to provide one.
  windows-bridge-profile-bin-installed =
    pkgs.runCommand "windows-bridge-profile-bin-installed" {
      installed = lib.boolToString (lib.elem homeWriteGuard homePackages);
      guard = homeWriteGuard.name;
    } ''
      if [ "$installed" != "true" ]; then
        echo "GUARD: $guard is named in the Windows settings.json fragment through"
        echo '       ~/.nix-profile/bin, but it is not in home.packages, so that path'
        echo '       does not exist. The WSL side keeps working -- it calls the same'
        echo '       program by store path -- and the Windows hook silently stops.'
        echo '       Add it to home.packages in modules/claude-code.nix.'
        exit 1
      fi
      touch $out
    '';

  # The home-root write rule is enforced on BOTH sides of the boundary.
  #
  # checks/claude-home-guard.nix proves the hook decides correctly, including on
  # the backslash and drive-letter paths only the Windows caller produces. It
  # cannot prove the Windows caller ever reaches it. That is this guard, and the
  # two together are the whole claim: the rule is right, and it runs.
  #
  # The failure this prevents is not a wrong decision but a missing one, and it
  # is invisible from the WSL side by construction -- `hms' would go on
  # installing the WSL hook, `nix flake check' would go on passing, and the only
  # symptom would be scratch files accumulating in C:\Users\<winuser>, which is
  # a directory nobody lists. That is precisely how 371 of them accumulated in
  # /home/gfoster.
  #
  # Asserted through ~/.nix-profile/bin rather than by store path, which
  # windows-bridge-no-store-paths independently forbids: between them, the
  # command has to be a profile name AND has to be this profile name.
  windows-bridge-home-guard-crosses =
    pkgs.runCommand "windows-bridge-home-guard-crosses" {
      nativeBuildInputs = [pkgs.jq];
      settings = winSettingsText;
      passAsFile = ["settings"];
    } ''
      for want in \
        PreToolUse:claude-home-guard \
        PostToolUse:"claude-home-guard detect"; do
        event=''${want%%:*}
        bin=''${want#*:}
        jq -e --arg e "$event" --arg b "$bin" \
          '[.hooks[$e][]?.hooks[]?.command] | any(endswith("/.nix-profile/bin/" + $b))' \
          "$settingsPath" > /dev/null \
          || { echo "GUARD: the Windows settings.json fragment runs no $bin on $event."; \
               echo '       The home-root write rule would then be enforced on the WSL side'; \
               echo '       only, while the Windows side went on writing scratch into'; \
               echo '       C:\Users\<winuser> with nothing to notice. See homeWriteGuard.'; \
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
