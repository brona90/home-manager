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
      nativeBuildInputs = [homeWriteGuard];
    } ''
      home=${builtins.toJSON homeDirectory}
      home=''${home//\"/}
      fails=0

      expect() { # label want json [env]
        label="$1"; want="$2"; json="$3"; envv="''${4:-IRRELEVANT=1}"
        set +e
        printf '%s' "$json" | env "$envv" claude-home-guard >/dev/null 2>&1
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
