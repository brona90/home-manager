# Guard: the hook that keeps scratch files out of the home root actually works.
#
# WHY A BEHAVIOURAL CHECK AND NOT JUST A SETTINGS ONE. checks/claude-settings.nix
# can confirm the hook is WIRED -- that settings.json names it under PreToolUse
# with the right matcher -- and that is worth confirming, so it is the first
# guard below. It cannot confirm the hook DECIDES correctly, and the difference
# is not academic: the first two versions of this script built cleanly, were
# wired identically, and were wrong. One shipped a `tr' that Nix's
# indented-string escaping had quietly reduced to a no-op; the next failed to
# build at all because a comment opened with a word the shell linter reads as a
# directive. A guard that only reads settings.json would have passed the first
# of those, which is exactly the silent-wrongness this repo writes guards to
# prevent.
#
# THE MATRIX BELOW IS THE RULE. Each row is one sentence of the policy stated in
# modules/claude-code.nix: non-hidden file directly in the home root is refused;
# a dotfile is configuration; one directory down is a project; another tool is
# not our business; the escape hatch is honoured. Changing the policy means
# changing a row here, which is the point -- the rule cannot drift from its test
# without one of them failing.
#
# Inputs, passed by checks/default.nix.
#   pkgs           -- `pkgsFor system` for the system being checked.
#   settingsText   -- rendered ~/.claude/settings.json, for the wiring guard.
#   homeWriteGuard -- the built guard package, read from the evaluated home
#                     configuration rather than rebuilt here, so this check
#                     exercises the same bytes activation installs.
#   homeDirectory  -- the home root the guard was built to protect. Taken from
#                     the same configuration for the same reason; hard-coding
#                     /home/gfoster here would make the check pass on a machine
#                     where the guard protects something else.
{
  pkgs,
  settingsText,
  homeWriteGuard,
  homeDirectory,
}: {
  # The hook is wired, on the tools whose path is declared and checkable.
  claude-home-guard-wired =
    pkgs.runCommand "claude-home-guard-wired" {
      nativeBuildInputs = [pkgs.jq];
      settings = settingsText;
      passAsFile = ["settings"];
    } ''
      jq -e '[.hooks.PreToolUse[]?.matcher] | index("Write|Edit|NotebookEdit") != null' "$settingsPath" >/dev/null \
        || { echo 'GUARD: PreToolUse must carry a Write|Edit|NotebookEdit matcher for the home guard'; exit 1; }
      jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | map(test("claude-home-guard")) | any' "$settingsPath" >/dev/null \
        || { echo 'GUARD: a PreToolUse hook must invoke claude-home-guard'; exit 1; }
      jq -e '[.hooks.PostToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command] | map(test("claude-home-guard detect")) | any' "$settingsPath" >/dev/null \
        || { echo 'GUARD: PostToolUse Bash must invoke the claude-home-guard detector'; exit 1; }
      touch $out
    '';

  # The hook decides correctly. One row per sentence of the policy.
  claude-home-guard-decides =
    pkgs.runCommand "claude-home-guard-decides" {
      # jq builds the Windows payloads below. Writing those by hand means
      # spelling a backslash through Nix, through the shell and through JSON at
      # once, and a row that is wrong in its own quoting tests the quoting
      # rather than the rule.
      nativeBuildInputs = [homeWriteGuard pkgs.jq];
    } ''
      home=${builtins.toJSON homeDirectory}
      home=''${home//\"/}
      fails=0

      # THROUGH A FILE, NOT A PIPE, and the difference is a real defect this
      # matrix had rather than a style choice. The escape-hatch rows exit before
      # reading stdin -- that is what the escape hatch IS -- so the writer's
      # `printf' can lose a race against the reader's exit and die of EPIPE.
      # Under the `pipefail' a Nix builder runs with, the pipeline then reports
      # the WRITER's failure, and the row fails having proved nothing about the
      # guard. It is a race, so it fails sometimes: the rows here were green for
      # as long as they happened to win. A redirect has no second process to
      # lose to.
      expect() { # label want json [env]
        label="$1"; want="$2"; json="$3"; envv="''${4:-IRRELEVANT=1}"
        printf '%s' "$json" > payload.json
        set +e
        env "$envv" claude-home-guard < payload.json >/dev/null 2>&1
        rc=$?
        set -e
        if [ "$rc" != "$want" ]; then
          echo "GUARD: $label -- got rc=$rc, want rc=$want"
          fails=$((fails + 1))
        fi
      }

      expect "non-hidden file in home root is refused" 2 \
        "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$home/foo.sh\"}}"
      expect "Edit is refused the same way" 2 \
        "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$home/aud99.sh\"}}"
      expect "NotebookEdit is refused the same way" 2 \
        "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$home/x.ipynb\"}}"
      expect "a dotfile is configuration, not debris" 0 \
        "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$home/.zshrc\"}}"
      expect "one directory down is a project" 0 \
        "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$home/orrery/foo.sh\"}}"
      expect "somewhere else entirely is not our business" 0 \
        "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/foo.sh\"}}"

      # THE WINDOWS ROWS. The same sentences of the same policy, spelled the way
      # the other Claude Code on this machine spells them. These are the tests
      # the note inside homeWriteGuard said were missing, and their absence was
      # the whole argument for not crossing the hook: a separator conversion
      # with nothing feeding it a separator is a conversion nobody has run.
      #
      # `someone' rather than this machine's Windows account, deliberately. The
      # rule recognises a profile root by SHAPE, so a synthetic name is not a
      # weaker test -- it is the correct one, and a row naming the real account
      # would pass just as happily against a guard that had been quietly
      # hardcoded to it.
      win='C:\Users\someone'

      # The UNC spelling IS tied to this configuration, because it names the WSL
      # home the guard was built to protect. Derived from $home for the reason
      # given at the top of this file: hardcoding /home/gfoster makes a check
      # that passes on a machine where the guard protects something else.
      unc='\\wsl.localhost\Debian'"''${home//\//\\}"

      p() { jq -cn --arg t "$1" --arg f "$2" '{tool_name:$t,tool_input:{file_path:$f}}'; }

      expect "a backslash path in a Windows profile root is refused" 2 \
        "$(p Write "$win\\foo.sh")"
      expect "a lowercase drive letter is the same drive" 2 \
        "$(p Write "c:\\Users\\someone\\foo.sh")"
      expect "the forward-slash spelling of the same path is refused" 2 \
        "$(p Write "C:/Users/someone/foo.sh")"
      expect "a Windows dotfile is configuration there too" 0 \
        "$(p Write "$win\\.gitconfig")"
      expect "one directory down is a project there too" 0 \
        "$(p Write "$win\\src\\foo.sh")"
      expect "a drive root is not a profile root" 0 \
        "$(p Write "D:\\foo.sh")"
      expect "a Windows path outside any profile is not our business" 0 \
        "$(p Write "C:\\dev\\foo.sh")"
      expect "the UNC spelling of the WSL home root is refused" 2 \
        "$(p Write "$unc\\foo.sh")"
      expect "the UNC spelling one directory down is a project" 0 \
        "$(p Write "$unc\\orrery\\foo.sh")"
      expect "the escape hatch is honoured on a Windows path too" 0 \
        "$(p Write "$win\\foo.sh")" CLAUDE_ALLOW_HOME_WRITE=1
      expect "another tool is not our business" 0 \
        '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
      expect "a payload with no tool is survivable" 0 '{}'
      expect "the escape hatch is honoured" 0 \
        "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$home/foo.sh\"}}" \
        CLAUDE_ALLOW_HOME_WRITE=1

      if [ "$fails" -ne 0 ]; then
        echo "GUARD: $fails home-guard decision(s) wrong"
        exit 1
      fi
      touch $out
    '';
}
