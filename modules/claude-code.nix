{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.claudeCode;

  # Named by every Windows-side command that calls back into WSL. See the
  # option in modules/windows-bridge.nix for why it is not left implicit.
  inherit (config.my.windowsBridge) wslDistro;

  # Hoisted out of the enabledPlugins keys to keep an at-sign-prefixed plugin
  # marketplace string out of the raw file text. GitHub's mention parser
  # greedy-matches the substring at-cl* (the plugins-official user 404s, so it
  # falls back to the bot user id 81847) and pulls that bot into the repo's
  # contributors widget. Splitting the literal preserves the evaluated value
  # Claude Code reads while avoiding the raw-text mention match in this file.
  marketplace = "claude-plugins-official";

  # WHY THIS GUARD EXISTS. A survey of this machine on 2026-08-29 found 371 loose
  # scripts sitting directly in /home/gfoster -- aud1.sh through aud15.sh,
  # brief-diag.sh, basecheck.sh -- and 303 of the 313 shell scripts among them
  # carried no exec bit, i.e. each was written to be run once as `bash foo.sh'
  # and never again. Several cd into worktrees that have since been removed, so
  # they cannot even be re-run. Every one is an agent answering a question where
  # it stood instead of in a scratchpad, and the instruction not to do that has
  # been in CLAUDE.md the whole time: an instruction is advice the model may not
  # be holding at the moment it reaches for Write, and a hook is not.
  #
  # THE RULE, and why it can afford to be this blunt: a NON-HIDDEN FILE written
  # directly into the home root is debris. Dotfiles are configuration and are
  # never touched. Anything one directory down is a project and is never
  # touched. A directory is not a file. What is left is exactly the shape those
  # 371 share and almost nothing legitimate, which is what makes a hard refusal
  # cheap here rather than merely irritating -- the escape hatch below exists
  # for the remainder and has to be set deliberately, per call.
  #
  # WHAT IT CANNOT SEE, and why it does not pretend to. Write/Edit/NotebookEdit
  # declare a path, so checking one is exact and a refusal is never wrong. A
  # `cat > ~/x.sh' inside a Bash call declares nothing, and matching a regex
  # against arbitrary shell to find it is a false-positive machine that would
  # get itself disabled within a week. So the Bash half is a PostToolUse
  # DETECTOR that reports and does not refuse: block what can be proved, report
  # what can only be noticed, and never guess in the blocking direction.
  homeWriteGuard = pkgs.writeShellApplication {
    name = "claude-home-guard";
    # `Nix PATH is login-shell only' applies with full force here: a hook is
    # started by Claude Code with /usr/bin, not with this user's profile, so
    # every binary this script names has to be listed. runtimeInputs prefixes
    # rather than replaces PATH, so an invocation from inside a login shell
    # still behaves identically.
    runtimeInputs = [pkgs.jq pkgs.coreutils pkgs.findutils];
    text = ''
      set -u

      root=${lib.escapeShellArg config.home.homeDirectory}

      # Deliberate, per-call, and named in the refusal text so the way out is
      # discoverable from the error rather than from this file.
      if [ "''${CLAUDE_ALLOW_HOME_WRITE:-}" = "1" ]; then
        exit 0
      fi

      mode="guard"
      if [ "$#" -gt 0 ]; then
        mode="$1"
      fi

      if [ "$mode" = "detect" ]; then
        # No stamp file and no session state: "changed in the last minute" is a
        # good enough proxy for "this Bash call did it", and being occasionally
        # late is harmless for something that only ever prints.
        #
        # ONE ROOT HERE, where the blocking half above has two, and the
        # asymmetry is not an oversight. A shape can be compared against a
        # declared path; it cannot be listed. A Bash call declares nothing, so
        # this half needs a directory NAME, and the only name it lacks -- the
        # Windows profile -- is the one discovered at activation. Giving it that
        # name means a state file written by the windows-bridge activation
        # script, a check that it still writes it, and an activation contract
        # between two modules that have so far shared only data. That is its own
        # change, for the same reason the conversion above was: it needs a guard
        # of its own, and a guard that can be missing is worse than a rule that
        # is honestly absent. What crosses today still earns its place -- a
        # Windows session runs most of its Bash inside WSL through wsl.exe, and
        # those writes land in the root this does scan.
        hits=$(find "$root" -maxdepth 1 -type f ! -name '.*' -mmin -1 -printf '%f\n' 2>/dev/null || true)
        if [ -n "$hits" ]; then
          printf 'claude-home-guard: these non-hidden files just appeared directly in %s:\n\n%s\n\nThat is where the 371 came from. Move them into the session scratchpad, or into the repo they serve with a name that says what they are, and remove them from the home root before finishing.\n' "$root" "$hits" >&2
          exit 2
        fi
        exit 0
      fi

      payload=$(cat)

      tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
      case "$tool" in
        Write | Edit | NotebookEdit) : ;;
        *) exit 0 ;;
      esac

      path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
      if [ -z "$path" ]; then
        exit 0
      fi

      # THREE SPELLINGS REACH THIS HOOK, because two Claude Codes work on the
      # same repositories. The WSL one declares /home/gfoster/foo.sh. The
      # Windows one declares C:\Users\brona\foo.sh when it writes into its own
      # profile, and \\wsl.localhost\Debian\home\gfoster\foo.sh when it writes
      # the very file this hook is looking at, from the outside. All three name
      # a home root, and the rule is about home roots rather than about
      # separators, so they are reduced to one spelling before it is applied.
      #
      # The note that stood here said normalising for a caller that did not
      # exist bought one escaping bug per attempt, for a case no test could
      # exercise. The caller exists now and the tests are in
      # checks/claude-home-guard.nix. The escaping fear turned out to be
      # misplaced in one specific way worth recording: backslash is NOT an
      # escape character inside a Nix indented string, so the literals below are
      # written once and read literally. It is the double-quoted Nix string that
      # would have doubled them.
      normalise_path() {
        # Backslashes to slashes first, so one set of patterns below covers both
        # the backslash spelling Windows normally hands over and the
        # forward-slash spelling it sometimes hands over instead.
        #
        # Both the doubling and the quotes are load-bearing, and the first draft
        # of this line had neither. `\/' is an ESCAPED SLASH, so the expansion
        # that reached the shell was ''${1//\/}: a pattern of `/' with an empty
        # replacement, which deletes every separator instead of converting any.
        # It fails on the WSL rows rather than the Windows ones -- a path with
        # no backslash in it is the shape the wrong version mangles worst -- so
        # it does not even fail where you would look for it. Same family as the
        # `tr' bug recorded above: a conversion flattened by a layer of escaping
        # between the source and the shell, silent in both directions, and found
        # only by running the built script against the matrix.
        local p="''${1//\\//}"

        case "$p" in
          # \\wsl.localhost\<distro>\... and the older \\wsl$\<distro>\... are
          # this filesystem seen from the other side. Drop the host and the
          # share -- they are the distro's UNC spelling, not directories -- and
          # what remains is a path this hook already understood.
          #
          # One pattern for both hosts. Matching `wsl$' exactly would put a `$'
          # inside a case pattern inside a Nix indented string, and the line
          # above is what that class of cleverness costs here; `wsl*' is a wider
          # net over a namespace where nothing else is reachable anyway.
          //wsl*/*/*) p="/''${p#//*/*/}" ;;
          # A drive letter means a Windows path. WSL mounts it at /mnt/<letter>,
          # lowercase, whatever case was typed at the other end.
          [A-Za-z]:/*)
            local drive="''${p%%:*}"
            p="/mnt/''${drive,,}/''${p#*:/}"
            ;;
        esac

        printf '%s' "$p"
      }

      # THE HOME ROOTS. One is known when this script is built: the WSL home
      # this configuration is for. The other cannot be. The Windows account name
      # is discovered at activation by asking cmd.exe, precisely because it is
      # not the WSL one on this machine and would be a third thing on the next
      # one -- so baking it in here would produce a guard that is right on
      # exactly one box and silently wrong everywhere else.
      #
      # It is therefore recognised by SHAPE rather than by name:
      # /mnt/<drive>/Users/<one component> is a profile root, whoever it belongs
      # to. A shape has no lookup to go stale, no state file to be missing, and
      # no way to be vacuously correct on a machine where the name was never
      # recorded -- which is worth more than the precision it gives up, since
      # what it gives up is the right to drop scratch into somebody else's
      # profile root, and that was never wanted either.
      is_home_root() {
        if [ "$1" = "$root" ]; then
          return 0
        fi
        case "$1" in
          # Deeper than a profile root is a project, and not our business. This
          # case has to precede the next one: a glob `*' matches slashes too, so
          # the shallower pattern would otherwise swallow both.
          /mnt/?/Users/*/*) return 1 ;;
          /mnt/?/Users/*) return 0 ;;
        esac
        return 1
      }

      path=$(normalise_path "$path")
      dir=$(dirname "$path")
      base=$(basename "$path")

      # Configuration, not debris. Never blocked.
      case "$base" in
        .*) exit 0 ;;
      esac

      if is_home_root "$dir"; then
        printf 'claude-home-guard: refusing to write %s\n\n%s is the home root, and a non-hidden file directly in it is scratch. Scratch belongs in the session scratchpad, or in the repo it serves under a name that says what it is. 371 files arrived this way before this hook existed; several of them cd into worktrees that no longer exist.\n\nIf this file genuinely belongs in the home root, re-run the call with CLAUDE_ALLOW_HOME_WRITE=1.\n' "$path" "$dir" >&2
        exit 2
      fi

      exit 0
    '';
  };

  # The server itself: a pinned tarball with its node_modules fetched by Nix.
  # See modules/porkbun-mcp/package.nix for why this is not `npx -y' and not the
  # bare-fetchzip shape claude-powerline uses below.
  porkbunMcpServer = pkgs.callPackage ./porkbun-mcp/package.nix {};

  porkbunMcpWrapper = pkgs.writeShellApplication {
    name = "porkbun-mcp";
    # nodejs is still here even though the exec below is a wrapped bin: the
    # bin/porkbun-mcp symlink points at dist/index.js, whose `#!/usr/bin/env
    # node' shebang needs a node on PATH.
    runtimeInputs = [pkgs.nodejs pkgs.coreutils];
    text = ''
      api_key_file="${config.home.homeDirectory}/.config/sops-nix/secrets/porkbun_api_key"
      secret_key_file="${config.home.homeDirectory}/.config/sops-nix/secrets/porkbun_secret_key"
      if [ ! -r "$api_key_file" ] || [ ! -r "$secret_key_file" ]; then
        echo "porkbun-mcp: secret files missing or unreadable" >&2
        exit 1
      fi
      PORKBUN_API_KEY=$(cat "$api_key_file")
      PORKBUN_SECRET_API_KEY=$(cat "$secret_key_file")
      export PORKBUN_API_KEY PORKBUN_SECRET_API_KEY
      # A store path, resolved at build time. The two secrets above are already
      # in this process's environment when the exec happens, so what runs here
      # must be decided by this repository and not by whoever last published to
      # the npm registry.
      exec ${lib.getExe porkbunMcpServer} "$@"
    '';
  };

  # Serialize the MCP servers contributed via my.claudeCode.mcpServers (this module
  # sets porkbun; claude-kg/searxng/emacs modules add their own) for the activation
  # merge below. Claude Code reads user-scope servers only from ~/.claude.json — never
  # from settings.json — so we merge into that mutable runtime file on every switch,
  # which also refreshes Nix-store command paths on each rebuild.
  managedMcpServersFile =
    pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON cfg.mcpServers);

  # claude-powerline ships fully bundled (no runtime npm dependencies), so we
  # pin the tarball and run it with node directly: the statusline re-runs on
  # every conversation update, where per-call npx resolution is too slow.
  claudePowerlineSrc = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@owloops/claude-powerline/-/claude-powerline-1.27.0.tgz";
    hash = "sha256-0l30qqQyGxYl1W++jOutzrQA0eQ6eUg9LdFwV9RhC10=";
  };

  # Hand-written JSON rather than builtins.toJSON: claude-powerline renders
  # segments in JSON key order, and toJSON sorts attrset keys alphabetically,
  # which would scramble the segment order. Segment lineup mirrors the
  # previous shell statusline: user@host, cwd, git branch, model, context %,
  # 5h rate limit (block), 7d rate limit (weekly).
  claudePowerlineConfig = pkgs.writeText "claude-powerline.json" ''
    {
      "theme": "dark",
      "display": {
        "style": "powerline",
        "charset": "unicode",
        "lines": [
          {
            "segments": {
              "env": {"enabled": true, "variable": "CLAUDE_POWERLINE_HOST", "prefix": ""},
              "directory": {"enabled": true, "style": "fish"},
              "git": {"enabled": true},
              "model": {"enabled": true},
              "context": {"enabled": true, "percentageMode": "used", "displayStyle": "text"},
              "block": {"enabled": true, "displayStyle": "text"},
              "weekly": {"enabled": true, "displayStyle": "text"}
            }
          }
        ]
      }
    }
  '';

  statusLineScript = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [pkgs.nodejs pkgs.git pkgs.coreutils];
    text = ''
      # No built-in hostname segment; feed user@host through the env segment.
      CLAUDE_POWERLINE_HOST="$(whoami)@$(hostname -s)"
      export CLAUDE_POWERLINE_HOST
      exec node ${claudePowerlineSrc}/bin/claude-powerline \
        --config=${claudePowerlineConfig} "$@"
    '';
  };

  # Hook commands are contributed by other modules (claude-kg today), and the
  # right timeout is a property of the command, not of the event: the same
  # script runs several times slower when Claude Code is running natively on
  # Windows and reaches the hook through wsl.exe, which adds seconds of interop
  # overhead on top of the native runtime. A single per-event literal cannot
  # express that, so every contributed command carries its own budget. A bare
  # command string is still accepted and takes the event's default timeout,
  # which keeps every existing list-of-strings call site valid.
  hookCommandType = defaultTimeout:
    lib.types.coercedTo lib.types.str (command: {inherit command;})
    (lib.types.submodule {
      options = {
        command = lib.mkOption {
          type = lib.types.str;
          description = "Command line Claude Code executes for this hook.";
        };
        timeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = defaultTimeout;
          description = ''
            Seconds Claude Code waits before killing the hook. Budget for the
            slowest caller rather than the measured one: a hook that takes N
            seconds natively takes roughly N plus 1 to 10 more when Claude Code
            runs on Windows and invokes it through wsl.exe.
          '';
        };
        windowsProfileBin = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Name of the wrapper under ~/.nix-profile/bin that the Windows-side
            Claude Code runs for this hook, or null for "this hook means nothing
            on Windows" -- which is the default, because most of them do not.

            A bare NAME rather than a command, and that restriction is the point.
            This host's settings.json is regenerated on every switch, so it can
            name /nix/store paths safely. The Windows one is MERGED into a file
            Claude Code also writes, and nothing revisits it between switches, so
            a store path recorded there goes on naming a generation that garbage
            collection can remove. The profile symlink is the only handle that
            survives a rebuild; taking a name means a caller cannot pass anything
            that would not. checks/windows-bridge.nix enforces it.

            May legitimately differ from `command': kg-capture-hook-win exists
            only because the Windows caller sends Windows paths that the WSL hook
            cannot stat.
          '';
        };
      };
    });

  # Every event renders its contributed commands the same way; only the list
  # and the default timeout baked into its type differ.
  hookEntries = commands:
    map (c: {
      type = "command";
      inherit (c) command timeout;
    })
    commands;

  # The same contributed lists, rendered for the OTHER Claude Code: the one
  # running natively on Windows against work that lives in WSL. It reaches these
  # scripts through wsl.exe, so the command is a crossing rather than a path and
  # the binary is named through the profile, for the reason on windowsProfileBin.
  #
  # Derived from the SAME list hookEntries reads, not from a second list beside
  # it, and that is the whole fix. These three hooks previously existed as
  # hand-written lines in C:\Users\<winuser>\.claude\settings.json: unreachable
  # by `hms', invisible to `nix flake check', and absent from a rebuilt machine,
  # so the WSL half of this box ran the knowledge graph and the Windows half only
  # did while that file survived. A hook that should not cross opts out by
  # leaving windowsProfileBin null, which records the decision next to the hook
  # instead of as an absence somewhere else.
  windowsHookEntries = commands:
    map (c: {
      type = "command";
      command = "MSYS_NO_PATHCONV=1 wsl.exe -d ${wslDistro} -- ${config.home.homeDirectory}/.nix-profile/bin/${c.windowsProfileBin}";
      inherit (c) timeout;
    })
    (lib.filter (c: c.windowsProfileBin != null) commands);

  settings = {
    # No agent attribution in commit messages or PR bodies (no
    # Co-Authored-By trailers, no "Generated with Claude Code" footers).
    attribution = {
      commit = "";
      pr = "";
    };
    statusLine = {
      type = "command";
      command = "${statusLineScript}/bin/claude-statusline";
    };
    enabledPlugins = {
      # Language servers for the languages in daily use (go-to-def, refs,
      # diagnostics). No first-party LSP exists for Nix/Fortran/Elisp/Bash.
      "lua-lsp@${marketplace}" = true;
      "pyright-lsp@${marketplace}" = true;
      "typescript-lsp@${marketplace}" = true;
      "gopls-lsp@${marketplace}" = true;
      # Claude-tooling authoring: this config builds MCP servers (claude-kg,
      # searxng, porkbun), agents/commands (specflow), and hooks constantly.
      "plugin-dev@${marketplace}" = true;
      "mcp-server-dev@${marketplace}" = true;
      "skill-creator@${marketplace}" = true;
      # hookify ships its own SessionStart/PreToolUse/PostToolUse/Stop/
      # UserPromptSubmit runners that execute in every session — enabled
      # deliberately, not as a default.
      "hookify@${marketplace}" = true;
    };
    # MCP servers are NOT set here — Claude Code ignores `mcpServers` in
    # settings.json. They are declared via my.claudeCode.mcpServers (by this and
    # other modules) and merged into ~/.claude.json by the activation script below.
    permissions = {
      allow = [
        "Bash(gh run view *)"
        "Bash(gh run list *)"
        "Bash(gh run watch *)"
        "Bash(gh pr view *)"
        "Bash(gh pr checks *)"
        "Bash(gh api *)"
        # emacs_eval is deliberately NOT allow-listed: it passes arbitrary
        # elisp to emacsclient --eval, which is an unguarded code-execution
        # path that bypasses every other permission gate.
        "mcp__emacs__emacs_show_diff"
      ];
    };
    hooks =
      {
        PermissionRequest = [
          {
            matcher = "Edit|Write";
            hooks = [
              {
                type = "command";
                # Write via temp file + mv in the same directory so input.json
                # appears atomically and readers never see a partial write.
                #
                # `-s $EMACS_SOCKET_NAME` when that is set, bare emacsclient
                # otherwise. A bare emacsclient resolves to whichever Emacs is
                # on PATH -- i.e. ALWAYS the daily driver -- so a Claude session
                # running inside a second daemon would fire its hook at the
                # wrong Emacs and show the diff there. Emacs does not export
                # EMACS_SOCKET_NAME to its subprocesses (it is read only by the
                # emacsclient binary), so the daemon's unit has to set it; where
                # it is unset this expands to nothing and behaviour is exactly
                # as before.
                command = "[ -n \"\${INSIDE_EMACS:-}\" ] || exit 0; d=\${XDG_RUNTIME_DIR:-/tmp}/claude-diff && mkdir -p \"$d\" && f=$d/input.json && t=$(mktemp \"$d/input.XXXXXX\") && cat > \"$t\" && mv \"$t\" \"$f\" && emacsclient \${EMACS_SOCKET_NAME:+-s \"$EMACS_SOCKET_NAME\"} --eval \"(claude-diff-from-hook \\\"$f\\\")\"";
                timeout = 10;
              }
            ];
          }
        ];
        # Exact, blocking, and only where the path is declared. See the
        # homeWriteGuard comment above for why the Bash case is a detector
        # instead and why the rule is allowed to be a flat refusal.
        PreToolUse = [
          {
            matcher = "Write|Edit|NotebookEdit";
            hooks = [
              {
                type = "command";
                command = "${homeWriteGuard}/bin/claude-home-guard";
                timeout = 5;
              }
            ];
          }
        ];
        PostToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${homeWriteGuard}/bin/claude-home-guard detect";
                timeout = 5;
              }
            ];
          }
          {
            matcher = "Edit|Write";
            hooks = [
              {
                type = "command";
                # Same socket handling as the PermissionRequest hook above --
                # the dismiss must reach the SAME Emacs that was asked to show
                # the diff, or the diff layout is left on screen forever.
                command = "[ -n \"\${INSIDE_EMACS:-}\" ] || exit 0; emacsclient \${EMACS_SOCKET_NAME:+-s \"$EMACS_SOCKET_NAME\"} --eval '(claude-diff-dismiss)'";
                timeout = 5;
              }
            ];
          }
        ];
      }
      // lib.optionalAttrs (cfg.sessionEndCommands != []) {
        # Run each contributed SessionEnd command (e.g. claude-kg auto-capture).
        SessionEnd = [{hooks = hookEntries cfg.sessionEndCommands;}];
      }
      // lib.optionalAttrs (cfg.sessionStartCommands != []) {
        # Contributed SessionStart commands (e.g. claude-kg recall primer). Each
        # command's stdout is injected into the new session's context.
        SessionStart = [{hooks = hookEntries cfg.sessionStartCommands;}];
      }
      // lib.optionalAttrs (cfg.userPromptSubmitCommands != []) {
        # Contributed UserPromptSubmit commands (e.g. claude-kg per-prompt recall).
        # Each command receives the prompt JSON on stdin and may inject context via stdout.
        UserPromptSubmit = [{hooks = hookEntries cfg.userPromptSubmitCommands;}];
      };
  };

  # Only the events with something to send. An event that renders to no entries
  # is left out of the fragment entirely rather than emitted as an empty list:
  # the merge would otherwise write `[]' over whatever that event holds on the
  # Windows side, which is the one way a merged fragment can destroy data.
  # The home-root guard, crossed. Unlike the three events below it this hook is
  # neither optional nor contributed: it is one policy with two enforcement
  # points, and the Windows one is where the writes it exists to stop are least
  # visible. A file dropped in /home/gfoster turns up in every `ls' anybody runs
  # there; a file dropped in C:\Users\<winuser> turns up in a directory nobody
  # lists, next to sixty of Windows' own.
  #
  # Named through the profile, not by store path, for the reason recorded on
  # windowsProfileBin: this fragment is MERGED into a file that is never
  # regenerated, so a /nix/store path written into it dangles at the next
  # rebuild and the hook stops running on one side only, silently -- which is
  # the exact failure this whole module was written to end.
  #
  # The timeout is the WSL one's 5 seconds plus room for a cold `wsl.exe' start,
  # which the WSL side never pays. A hook that times out does not fail loudly;
  # it just stops deciding, so the number that matters is the slow case.
  windowsHomeGuardCommand = "MSYS_NO_PATHCONV=1 wsl.exe -d ${wslDistro} -- ${config.home.homeDirectory}/.nix-profile/bin/claude-home-guard";

  windowsHooks =
    {
      PreToolUse = [
        {
          matcher = "Write|Edit|NotebookEdit";
          hooks = [
            {
              type = "command";
              command = windowsHomeGuardCommand;
              timeout = 15;
            }
          ];
        }
      ];
      PostToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "${windowsHomeGuardCommand} detect";
              timeout = 15;
            }
          ];
        }
      ];
    }
    // lib.optionalAttrs (windowsHookEntries cfg.sessionEndCommands != []) {
      SessionEnd = [{hooks = windowsHookEntries cfg.sessionEndCommands;}];
    }
    // lib.optionalAttrs (windowsHookEntries cfg.sessionStartCommands != []) {
      SessionStart = [{hooks = windowsHookEntries cfg.sessionStartCommands;}];
    }
    // lib.optionalAttrs (windowsHookEntries cfg.userPromptSubmitCommands != []) {
      UserPromptSubmit = [{hooks = windowsHookEntries cfg.userPromptSubmitCommands;}];
    };

  # WHAT THE FLAKE CLAIMS IN THE WINDOWS settings.json -- and what it refuses to.
  #
  # This is a merged fragment, so naming a key here makes the flake authoritative
  # for it: activation overwrites it and reports any difference as drift. A key
  # left out is left entirely to Claude Code. The split is by WHO WRITES THE KEY,
  # not by what it means, because that is the only criterion under which claiming
  # a key cannot destroy someone else's writes.
  #
  # CLAIMED.
  #   attribution -- policy, the same decision on both sides, and the reason this
  #     fragment exists at all. See checks/windows-bridge.nix.
  #   hooks.SessionStart / UserPromptSubmit / SessionEnd -- flake-built programs
  #     whose only writer is this repository. Claiming them is the point of the
  #     exercise; see windowsHookEntries above.
  #   statusLine -- names statusline-command.sh, which this module now installs
  #     as an owned bridge file. The key and the script have to arrive together:
  #     shipping the script while leaving the key unclaimed would install a
  #     statusline nothing invokes, and claiming the key without the script would
  #     name one that is not there.
  #   hooks.PreToolUse / PostToolUse -- the home-root write guard. Same writer as
  #     the other hook events, and now the same story: the note inside
  #     homeWriteGuard said crossing it needed a separator conversion and a test
  #     that feeds it a backslash, and it has both. It arrives with the same
  #     pairing requirement statusLine has -- the command names
  #     ~/.nix-profile/bin/claude-home-guard, so the package is in home.packages,
  #     and claiming the key without that would name a binary that is not there.
  #
  # NOT CLAIMED, each for a named writer rather than out of general caution.
  #   permissions -- Claude Code appends to permissions.allow every time a rule
  #     is approved with "always allow", and jq's `*' REPLACES arrays instead of
  #     merging them, so claiming this would delete every rule approved since the
  #     last switch, on every switch. The two lists also differ legitimately: the
  #     Windows one carries PowerShell() rules that are meaningless in WSL and
  #     omits mcp__emacs__emacs_show_diff, there being no emacs MCP server
  #     registered on that side.
  #   enabledPlugins / extraKnownMarketplaces -- written by installing a plugin.
  #     Claiming them would silently revert every future install, which is a
  #     worse bug than the drift it would close.
  #   autoMode.environment -- Claude Code generates it from the machine it is on,
  #     and it is correctly different there.
  #   env, model, tui, autoUpdatesChannel, autoCompactWindow and the remaining
  #     preference keys -- written by the settings UI on that machine.
  #
  # Nothing is absent for a third reason any more. The one entry that used to be
  # -- hooks.PreToolUse / PostToolUse, "they simply do not work over there yet"
  # -- has moved up into CLAIMED, which is what closed the last gap this module
  # knew about in its own coverage.
  windowsSettings =
    {
      inherit (settings) attribution;

      # Deliberately NOT the claude-powerline statusline rendered for the WSL
      # side. Its `block' and `weekly' segments read the usage ledger under
      # ~/.claude/projects, and a Windows session's ledger is the one under
      # C:\Users, so pointing Windows at the WSL binary would confidently report
      # the wrong machine's rate limits. Two programs for two data sources:
      # one-sided by design, but flake-owned rather than hand-maintained.
      #
      # `bash <file>' rather than executing it directly -- the bridge installs
      # its files mode 644, and a DrvFs exec bit is not a thing to depend on.
      statusLine = {
        type = "command";
        command = "bash ~/.claude/statusline-command.sh";
      };
    }
    // lib.optionalAttrs (windowsHooks != {}) {hooks = windowsHooks;};
in {
  options.my.claudeCode = {
    enable = lib.mkEnableOption "Claude Code settings and hooks";

    # Read by checks/claude-home-guard.nix so the guard's behavioural test
    # exercises the package activation installs rather than a rebuild of the
    # same source. Internal and read-only: this is an output of the module, not
    # a knob -- nothing outside the check set has any business setting it.
    homeWriteGuardPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = homeWriteGuard;
      description = "The built claude-home-guard hook, exposed for the flake checks.";
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = ''
        User-scope MCP servers to merge into ~/.claude.json on activation. Other
        modules contribute entries (e.g. claude-kg, searxng, emacs-mcp); this module
        adds porkbun.
      '';
    };

    sessionEndCommands = lib.mkOption {
      type = lib.types.listOf (hookCommandType 15);
      default = [];
      description = ''
        Commands run as Claude Code SessionEnd hooks (one hook each). An entry is
        either a bare command string, which gets the 15s default timeout, or an
        attrset carrying a command and its own timeout in seconds.
      '';
    };

    sessionStartCommands = lib.mkOption {
      type = lib.types.listOf (hookCommandType 15);
      default = [];
      description = ''
        Commands run as Claude Code SessionStart hooks (one hook each). Each
        command's stdout is injected into the new session's context. An entry is
        either a bare command string, which gets the 15s default timeout, or an
        attrset carrying a command and its own timeout in seconds. 15s is only
        safe for a hook that touches nothing but the local filesystem: the
        wsl.exe crossing alone has been measured to add 9s to a hook that takes
        under 7s natively, so anything that also talks to a service should state
        its own timeout.
      '';
    };

    userPromptSubmitCommands = lib.mkOption {
      type = lib.types.listOf (hookCommandType 45);
      default = [];
      description = ''
        Commands run as Claude Code UserPromptSubmit hooks (one hook each). Each
        receives the prompt JSON on stdin and may inject context via stdout. An
        entry is either a bare command string, which gets the 45s default
        timeout, or an attrset carrying a command and its own timeout in
        seconds. The default is generous because this event blocks every turn on
        work that may have to cold-start an embedding model.
      '';
    };

    claudeMdSections = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Markdown sections contributed by modules; joined into the managed
        ~/.claude/CLAUDE.md (user-scope global instructions). Empty = file unmanaged.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # One `my' block rather than four assignments to it: statix W20 refuses the
    # repeated key, and the pre-commit hook refuses the commit. Worth stating
    # because the three Windows entries below were added together and the lint
    # only fires once there is more than one -- the single porkbun assignment
    # that stood here before was silent.
    my = {
      # This module owns the porkbun DNS MCP server (its wrapper is defined above).
      claudeCode.mcpServers.porkbun = {
        type = "stdio";
        command = "${porkbunMcpWrapper}/bin/porkbun-mcp";
      };

      windowsBridge.files = {
        # The OTHER settings.json: the one Claude Code reads when it runs natively on
        # Windows against work that lives in WSL. Installed by
        # modules/windows-bridge.nix (a no-op anywhere there is no /mnt/c), declared
        # here because this module owns what Claude Code is configured to do.
        #
        # MERGED, not owned: Claude Code writes that file itself, so the fragment
        # claims named keys and leaves the rest alone. windowsSettings above is the
        # list of what is claimed, with the writer-by-writer reason for everything
        # that is not.
        #
        # Every value comes from the definitions above BY REFERENCE, not by copy:
        # one definition in this repo, read by both files and by both guards. They
        # live here rather than in windows-bridge.nix because what Claude Code is
        # configured to do is a Claude Code decision, not a Windows one.
        claude-settings = {
          target = ".claude/settings.json";
          mode = "merge-json";
          text = builtins.toJSON windowsSettings;
        };

        # The statusline the fragment above names. OWNED rather than merged: a whole
        # file with a single writer -- a human, once; Claude Code has never written
        # it -- which is exactly the criterion modules/windows-bridge.nix sets out
        # for `own'. It existed only on the Windows disk until now, so a rebuilt
        # machine got a settings.json naming a script that was not there, and a
        # statusline that silently rendered nothing.
        #
        # Kept byte-for-byte as found. Its job in this change is to become
        # reproducible, not to become better: rewriting a working statusline in the
        # same commit that first brings it under management would make any resulting
        # breakage impossible to attribute.
        claude-statusline = {
          target = ".claude/statusline-command.sh";
          mode = "own";
          text = builtins.readFile ./claude-statusline-windows.sh;
        };

        # The same sections, joined the same way, for the same reason -- and the
        # sharpest asymmetry of the lot, because C:\Users\<winuser>\.claude\CLAUDE.md
        # did not exist at all. The knowledge-graph hooks have been firing on the
        # Windows side and injecting recall into every session there, while the
        # standing directive that tells the model to CONTRIBUTE back -- call
        # kg_recall before non-trivial work, persist durable facts with kg_upsert_entity
        # -- lives in claude-kg's CLAUDE.md section and was reaching only WSL. Windows
        # sessions have been spending the graph without ever adding to it.
        #
        # `own' matches the WSL side, which renders this file from `text' and so
        # already treats it as flake-owned; the `#' memory shortcut cannot append to
        # a read-only store symlink there either. Guarded by the same condition as
        # the WSL file, so a host contributing no sections gets neither.
        claude-md = lib.mkIf (cfg.claudeMdSections != []) {
          target = ".claude/CLAUDE.md";
          mode = "own";
          text = lib.concatStringsSep "\n\n" cfg.claudeMdSections;
        };
      };
    };

    home = {
      # The module that enables Claude Code also owns the CLI package
      # (previously duplicated in home/linux.nix and home/darwin.nix).
      #
      # homeWriteGuard is in the profile because the Windows settings fragment
      # names it BY NAME under ~/.nix-profile/bin rather than by store path --
      # see windowsProfileBin, and see statusline-command.sh for what naming a
      # thing the flake does not install actually costs. The WSL side still
      # invokes it by store path, so this is the only thing making the Windows
      # command resolve to anything at all.
      packages = [pkgs.claude-code homeWriteGuard];

      file.".claude/settings.json".text = builtins.toJSON settings;

      # Assemble ~/.claude/CLAUDE.md (user-scope global instructions) from sections
      # contributed by modules (e.g. claude-kg, claude-specflow). Only managed when at
      # least one section is contributed, so the file is untouched on hosts with none.
      file.".claude/CLAUDE.md" = lib.mkIf (cfg.claudeMdSections != []) {
        text = lib.concatStringsSep "\n\n" cfg.claudeMdSections;
      };

      # Claude Code loads user-scope MCP servers only from ~/.claude.json (a mutable
      # runtime file), so we merge our managed set into it on activation instead of
      # owning the file. Unmanaged servers already present are preserved; ours win on
      # key conflict. Writes atomically via a temp file.
      activation.claudeMcpServers = lib.hm.dag.entryAfter ["writeBoundary"] ''
        cj="$HOME/.claude.json"
        ${pkgs.coreutils}/bin/test -e "$cj" || echo '{}' > "$cj"
        tmp="$(${pkgs.coreutils}/bin/mktemp "$HOME/.claude.json.XXXXXX")"
        if ${pkgs.jq}/bin/jq --slurpfile m ${managedMcpServersFile} \
             '.mcpServers = ((.mcpServers // {}) + $m[0])' "$cj" > "$tmp"; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$tmp" "$cj"
          echo "claude-mcp: merged managed MCP servers into ~/.claude.json"
        else
          ${pkgs.coreutils}/bin/rm -f "$tmp"
          echo "claude-mcp: jq merge failed; ~/.claude.json left unchanged" >&2
        fi
      '';
    };
  };
}
