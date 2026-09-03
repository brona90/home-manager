# The Windows half of this machine, made reproducible from the flake.
#
# WHY THIS EXISTS. Claude Code and Gpg4win run natively on Windows against work
# that lives in WSL, so a handful of files under C:\Users\<winuser> are
# load-bearing for this configuration -- and none of them are reachable by
# home-manager. `hms' cannot see them, `nix flake check' cannot guard them, and a
# fresh machine does not get them. Two failures came straight out of that gap:
#
#   * %APPDATA%\gnupg\scdaemon.conf had to be hand-edited with `pcsc-shared'
#     before the YubiKey worked at all, and nothing recorded that it had to be.
#     The diagnosis is the long comment above gpg-scd-shared() in modules/gpg.nix.
#   * The Windows ~/.claude/settings.json drifted from the WSL one and lost the
#     empty `attribution' block, so commits made from a Windows Claude session
#     carried Co-Authored-By trailers that the same work done from WSL did not --
#     while checks/claude-settings.nix went on passing, because the only
#     settings.json it has ever seen is the WSL one.
#
# WHAT IT DOES. Modules declare Windows-side files through
# `my.windowsBridge.files'; this module renders each one into the Nix store and
# copies it into the Windows profile on activation. The DECLARING module keeps
# ownership of the content -- modules/gpg.nix for the two gnupg configs,
# modules/claude-code.nix for the Claude settings fragment -- so a value that
# exists on both sides of the WSL boundary (the PIN cache TTLs, the attribution
# block) has exactly one definition and cannot drift by being edited in one
# place. This module is only the transport and the drift alarm; it knows nothing
# about gnupg or Claude Code.
#
# OWN vs MERGE-JSON. `own' rewrites the whole file; `merge-json' merges a managed
# JSON fragment into a file somebody else also writes. The choice is not
# stylistic. Owning a file that an application rewrites is how settings get
# silently deleted: the live Windows settings.json carries an `autoMode.environment'
# block Claude Code generates itself, an `enabledPlugins' entry added by
# installing a plugin, and permission rules the application appends every time
# one is approved with "always allow". Owning it would throw all of that away on
# the next `hms', which is a worse bug than the one being fixed. So config files
# with a single writer (the two gnupg ones -- Gpg4win never writes them; only a
# human or gpg-win-setup does -- and .claude/statusline-command.sh, written once
# by hand and never by Claude Code) are owned, and files with a live application
# writer are merged, claiming only the keys the flake is prepared to be
# authoritative for.
#
# DRIFT. These files live outside the Nix store on a filesystem other programs
# and other people write to, so "just overwrite" would hide exactly the edits
# worth knowing about (the hand-added `pcsc-shared' was such an edit, and it
# stayed undocumented for months). Owned files are therefore compared three ways:
# against the new rendering, and against the PREVIOUS rendering, kept under
# $XDG_STATE_HOME/windows-bridge. A target that matches neither was changed by
# something other than this module; that case prints a labelled diff, saves the
# file as `<target>.bak-<hash-of-its-content>' and only then installs the
# flake's version. Same content always yields the same backup name, so re-running
# activation cannot pile up backups. Merged files need no history: drift is
# "merging the managed fragment would change the file", which is a property of
# the file as it stands.
#
# NO-OP OFF WSL. Two gates, deliberately. Eval time: `my.windowsBridge.enable',
# set only in home/hosts/wsl.nix, so a Darwin or plain-Linux build never renders
# any of this and home/darwin.nix keeps building. Run time: the activation script
# still checks that /mnt/c is mounted and that cmd.exe answers, because the WSL
# host itself boots without them when interop or automount is off, and a switch
# must survive that. A bare `[ -d /mnt/c ]' test with no option would have been
# enough to make it harmless on a Mac, but it would put Windows-specific
# activation code into every configuration this repo builds; the option keeps the
# Windows machinery where the Windows machine is, next to my.gpg.forwardToWindows.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.windowsBridge;

  coreutils = "${pkgs.coreutils}/bin";
  diffutils = "${pkgs.diffutils}/bin";
  jq = "${pkgs.jq}/bin/jq";
  sed = "${pkgs.gnused}/bin/sed";

  # Where the previous rendering of each owned file is remembered, so that
  # "changed since we last wrote it" can be told apart from "we are changing it".
  stateDir = "${config.xdg.stateHome}/windows-bridge";

  # One store path per managed file. Rendering through writeText rather than
  # embedding the text in the script means the guard in checks/windows-bridge.nix
  # and the activation script are looking at the same bytes.
  rendered =
    lib.mapAttrs
    (name: f: pkgs.writeText "windows-bridge-${name}" f.text)
    cfg.files;

  # One dispatch line per file, in attribute-name order so the script is
  # reproducible. Names, modes and relative targets come from the option, so a
  # module can add a file without touching this one.
  syncCalls =
    lib.concatMapStringsSep "\n"
    (
      name: let
        f = cfg.files.${name};
      in "  windowsBridgeFile ${lib.escapeShellArg name} ${lib.escapeShellArg f.mode} ${lib.escapeShellArg f.target} ${rendered.${name}}"
    )
    (lib.attrNames cfg.files);
in {
  options.my.windowsBridge = {
    enable =
      lib.mkEnableOption
      "syncing flake-rendered configuration into the Windows user profile from WSL";

    # Not read by this module, which is only the transport. It is declared here
    # because it is a fact about THIS WSL/Windows boundary rather than about any
    # program that crosses it, so the second consumer finds it already named
    # instead of hardcoding the distro again.
    wslDistro = lib.mkOption {
      type = lib.types.str;
      default = "Debian";
      example = "NixOS";
      description = ''
        Name of this WSL distribution as `wsl.exe -d' spells it; `wsl.exe -l -q'
        lists them. Windows-side commands that call back into WSL have to name
        it explicitly. Omitting `-d' would use the Windows default distribution,
        which is a per-machine setting this flake does not control and cannot
        see -- so the hooks would run against whichever distro someone last set
        as default, or fail, depending on a value outside the repository.
      '';
    };

    files = lib.mkOption {
      default = {};
      description = ''
        Files this configuration maintains inside the Windows user profile,
        keyed by a short name used for the state file and in activation output.
        Contributed by the module that owns the content, never written here.
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          target = lib.mkOption {
            type = lib.types.str;
            example = "AppData/Roaming/gnupg/gpg-agent.conf";
            description = ''
              Path relative to the Windows user profile (C:\Users\<winuser>),
              written with forward slashes. The Windows user name is discovered
              at activation time and is never configured here: it differs from
              the WSL user name on this machine and again on any other.
            '';
          };

          mode = lib.mkOption {
            type = lib.types.enum ["own" "merge-json"];
            default = "own";
            description = ''
              "own" replaces the whole file with `text`; use it only where this
              flake is the single writer. "merge-json" treats `text` as a JSON
              fragment and merges it into an existing JSON file, claiming those
              keys and leaving every other key to whichever application writes
              the file. Merging is the safe default for anything an application
              rewrites by itself.
            '';
          };

          text = lib.mkOption {
            type = lib.types.lines;
            description = ''
              File content for mode "own", or the managed JSON fragment for mode
              "merge-json". Written to the Nix store as-is, with Unix line
              endings; comparison against the live file ignores carriage
              returns, so a Windows editor re-saving it as CRLF is not drift.
            '';
          };
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.windowsBridge = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Two files differ only by line endings? Not drift. Windows editors save
      # CRLF (the hand-added scdaemon.conf on this machine is "pcsc-shared\r\n")
      # and gpg reads both, so comparing raw bytes would rewrite the file on
      # every single activation and report drift that is not there.
      windowsBridgeSame() {
        ${diffutils}/cmp -s \
          <(${coreutils}/tr -d '\r' < "$1") \
          <(${coreutils}/tr -d '\r' < "$2")
      }

      # Copy $1 over $2 through a temp file in the TARGET directory, so a
      # half-written config never exists under that name. Same swap, and the
      # same copy fallback, as gpg-win-setup(): rename is not always honoured
      # across the Windows mount.
      windowsBridgeInstall() {
        local dir tmp
        dir=$(${coreutils}/dirname "$2")
        tmp=$(${coreutils}/mktemp "$dir/.windows-bridge.XXXXXX") || return 1
        if ! ${coreutils}/cat "$1" > "$tmp"; then
          ${coreutils}/rm -f "$tmp"
          return 1
        fi
        ${coreutils}/chmod 644 "$tmp" || true
        if ! ${coreutils}/mv -f "$tmp" "$2" 2>/dev/null; then
          if ! ${coreutils}/cp "$tmp" "$2"; then
            ${coreutils}/rm -f "$tmp"
            return 1
          fi
          ${coreutils}/rm -f "$tmp"
        fi
      }

      # Save the file as it stands and print where it went. The suffix is the
      # hash of the CONTENT, not a timestamp: an unchanged file backed up twice
      # lands on the same name instead of leaving a trail of near-identical
      # copies next to a config gpg has to parse.
      windowsBridgeBackup() {
        local sum backup
        sum=$(${coreutils}/sha256sum "$1" | ${coreutils}/cut -c1-12)
        backup="$1.bak-$sum"
        ${coreutils}/cp -f "$1" "$backup" || return 1
        printf '%s\n' "$backup"
      }

      # An owned file: this flake is the only writer, so anything else that
      # touched it is drift and gets said out loud before it is replaced.
      windowsBridgeOwn() {
        local target="$1" src="$2" state="$3"
        local backup

        if [ ! -e "$target" ]; then
          if windowsBridgeInstall "$src" "$target"; then
            echo "windows-bridge: created $target"
          else
            echo "windows-bridge: FAILED to create $target" >&2
            return 0
          fi
        elif windowsBridgeSame "$target" "$src"; then
          : # already exactly what the flake renders
        elif [ -e "$state" ] && windowsBridgeSame "$target" "$state"; then
          # Untouched since the last activation, so the difference is ours: the
          # flake changed. Update quietly-but-visibly, no backup needed.
          if windowsBridgeInstall "$src" "$target"; then
            echo "windows-bridge: updated $target"
          else
            echo "windows-bridge: FAILED to update $target" >&2
            return 0
          fi
        else
          # Matches neither the previous rendering nor the new one: somebody or
          # something else edited it. This is the case the whole module exists
          # to surface, so it is loud, it shows the diff, and it keeps the file.
          backup=$(windowsBridgeBackup "$target") || backup=""
          echo ""
          echo "windows-bridge: DRIFT  $target"
          echo "    This file is managed by the flake but was changed on the Windows side."
          if [ -n "$backup" ]; then
            echo "    Your version has been kept at:"
            echo "      $backup"
          else
            echo "    WARNING: the backup copy failed; your version is about to be lost." >&2
          fi
          echo "    Diff (yours -> flake):"
          ${diffutils}/diff -u "$target" "$src" | ${sed} 's/^/      /' || true
          echo "    If that change was deliberate, put it in the flake and rebuild;"
          echo "    editing this file again will only be overwritten next switch."
          echo ""
          if ! windowsBridgeInstall "$src" "$target"; then
            echo "windows-bridge: FAILED to install $target" >&2
            return 0
          fi
        fi

        # Remember what the flake rendered, so the next activation can tell
        # "the user edited it" from "the flake changed".
        ${coreutils}/cp -f "$src" "$state" || true
      }

      # A file with another writer: merge in the managed keys and leave the rest
      # alone. Drift is simply "merging would change something", which needs no
      # remembered state -- it is a property of the file as it stands right now.
      windowsBridgeMergeJson() {
        local target="$1" src="$2"
        local backup tmp

        if [ ! -e "$target" ]; then
          if windowsBridgeInstall "$src" "$target"; then
            echo "windows-bridge: created $target with the managed keys"
          else
            echo "windows-bridge: FAILED to create $target" >&2
          fi
          return 0
        fi

        if ! ${jq} -e . "$target" > /dev/null 2>&1; then
          echo "windows-bridge: $target is not valid JSON; refusing to merge into it." >&2
          echo "                Managed keys are NOT applied there. Fix the file and re-run hms." >&2
          return 0
        fi

        # `$t * $f == $t' is exactly "the managed fragment is already in there
        # with these values", recursively, without caring about any other key.
        if ${jq} -e --slurpfile f "$src" '. as $t | ($t * $f[0]) == $t' "$target" > /dev/null; then
          return 0
        fi

        backup=$(windowsBridgeBackup "$target") || backup=""
        echo ""
        echo "windows-bridge: DRIFT  $target"
        echo "    Keys this flake manages differ from the flake's values:"
        ${jq} -r --slurpfile f "$src" '
          . as $t
          | [$f[0] | paths(scalars)]
          | map(. as $p | select(($t | getpath($p)) != ($f[0] | getpath($p))))
          | .[]
          | "      ." + (map(tostring) | join("."))
        ' "$target" || true
        if [ -n "$backup" ]; then
          echo "    Previous version kept at:"
          echo "      $backup"
        fi
        echo "    Every other key in the file is left untouched."
        echo ""

        tmp=$(${coreutils}/mktemp) || return 0
        if ${jq} --slurpfile f "$src" '. * $f[0]' "$target" > "$tmp" \
          && windowsBridgeInstall "$tmp" "$target"; then
          echo "windows-bridge: merged managed keys into $target"
        else
          echo "windows-bridge: FAILED to merge managed keys into $target" >&2
        fi
        ${coreutils}/rm -f "$tmp"
      }

      windowsBridgeFile() {
        local name="$1" mode="$2" rel="$3" src="$4"
        local target="$WINDOWS_BRIDGE_HOME/$rel"
        local dir

        dir=$(${coreutils}/dirname "$target")
        if ! ${coreutils}/mkdir -p "$dir"; then
          echo "windows-bridge: cannot create $dir; skipping $rel" >&2
          return 0
        fi

        case "$mode" in
          own) windowsBridgeOwn "$target" "$src" "$WINDOWS_BRIDGE_STATE/$name" ;;
          merge-json) windowsBridgeMergeJson "$target" "$src" ;;
          *) echo "windows-bridge: unknown mode '$mode' for $name" >&2 ;;
        esac
      }

      # Wrapped in a function so the early exits below are `return', not `exit'.
      # home-manager concatenates every module's fragment into one script under
      # `set -eu -o pipefail', where a bare `exit' would abandon the whole switch
      # because a Windows mount was missing.
      windowsBridgeSync() {
        local cmdexe=/mnt/c/Windows/System32/cmd.exe
        local winuser

        # Run-time half of the no-op gate (the eval-time half is
        # my.windowsBridge.enable, set only in home/hosts/wsl.nix). This host
        # boots without /mnt/c when interop or automount is off; a switch there
        # must still succeed, and must say why it did nothing.
        if [ ! -d /mnt/c ]; then
          echo "windows-bridge: /mnt/c is not mounted; Windows-side files left alone."
          return 0
        fi
        if [ ! -x "$cmdexe" ]; then
          echo "windows-bridge: $cmdexe missing; Windows-side files NOT updated." >&2
          return 0
        fi

        # Same discovery gpg-win-setup() uses: ask cmd.exe and strip the CR it
        # appends. Hardcoding is not an option -- the Windows account name is
        # not the WSL one on this machine, let alone on another.
        winuser=$("$cmdexe" /c "echo %USERNAME%" 2>/dev/null | ${coreutils}/tr -d '\r\n')
        if [ -z "$winuser" ]; then
          echo "windows-bridge: could not read %USERNAME%; Windows-side files NOT updated." >&2
          return 0
        fi

        WINDOWS_BRIDGE_HOME="/mnt/c/Users/$winuser"
        if [ ! -d "$WINDOWS_BRIDGE_HOME" ]; then
          echo "windows-bridge: $WINDOWS_BRIDGE_HOME does not exist; Windows-side files NOT updated." >&2
          return 0
        fi

        WINDOWS_BRIDGE_STATE="${stateDir}"
        if ! ${coreutils}/mkdir -p "$WINDOWS_BRIDGE_STATE"; then
          echo "windows-bridge: cannot create $WINDOWS_BRIDGE_STATE; Windows-side files NOT updated." >&2
          return 0
        fi

      ${syncCalls}
      }

      # DRY_RUN_CMD is empty on a real switch and "echo" under `hms -n'. Nothing
      # here is a single command that could simply be prefixed with it, so the
      # whole traversal is skipped instead of half-simulated.
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "windows-bridge: dry run; would sync ${toString (lib.length (lib.attrNames cfg.files))} file(s) into the Windows user profile"
      else
        windowsBridgeSync
      fi
    '';
  };
}
