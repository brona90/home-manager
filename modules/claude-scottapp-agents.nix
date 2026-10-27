# ScottApp's project subagents, installed at USER scope.
#
# WHY. feature-builder, pr-integrator and coverage-raiser live in the ScottApp
# repository under .claude/agents/, where Claude Code loads them only for a
# session whose working directory is inside that checkout. The session that
# dispatches ScottApp work usually is not: the Windows-native Claude Code runs
# from C:\Users\<winuser>, and a WSL session started in $HOME is no better. So
# the agents the repo depends on were invisible to the session that needed them.
#
# ONE COPY OF THE TEXT. The repository stays the only place the agents are
# written. They are reviewed there and pinned by its tests/guards/
# project-agents.test.ts; a second, hand-maintained copy here would drift the
# way the hand-copied Windows skills did (see modules/claude-skills.nix). This
# module therefore stores NO agent text at all -- it renders each agent from
# the checkout when home-manager activates.
#
# WHY NOT A FLAKE INPUT. A pinned `scottapp' input was the obvious shape and is
# ruled out by visibility, not taste: ScottApp is a PRIVATE repository and this
# one is PUBLIC. CI fetches inputs with the workflow's GITHUB_TOKEN, which is
# scoped to this repository and cannot read another private one, so every job
# that evaluates the flake -- `nix flake check', the activation-package dry
# runs, the daily update-flake.yml lock bump -- would fail at fetch time, as
# would any fork. A `git+file' input to the checkout fails the same way and
# additionally bakes one machine's path into flake.lock. Making either work
# means handing CI a credential for the private repo, which is the owner's call
# and not a side effect of installing three markdown files.
#
# WHY NOT A SYMLINK INTO THE CHECKOUT. It would follow the WORKING TREE: an agent
# editing .claude/agents/ on a feature branch in that checkout would change the
# user-level agent of every session on the machine, before review. There is
# nowhere to put the preamble below, a symlink into WSL means nothing to the
# Windows side, and a moved checkout leaves it dangling with no message.
#
# WHAT THIS DOES INSTEAD. At activation, read each agent from a COMMITTED ref of
# the checkout (`origin/main' by default: the merged, reviewed state, not
# whatever branch is checked out), rename it and prepend a generated preamble,
# and write the result under $XDG_STATE_HOME/scottapp-agents. That one rendering
# is then consumed twice, like the bundle in modules/claude-skills.nix: a
# home.file symlink puts it in ~/.claude/agents, and my.windowsBridge copies the
# same bytes into C:\Users\<winuser>\.claude\agents.
#
#   * An update reaches users on the next `hms' after the checkout's ref has
#     moved (any `git fetch' in it moves origin/main). No lock bump.
#   * Checkout absent, moved, or the ref missing: activation says so and leaves
#     the previous rendering installed. Nothing is deleted; a stale agent with a
#     loud message beats a vanished one. Point `checkout' at the new location.
#   * An agent whose front matter no longer has `name: <filename>' (the repo
#     guard pins exactly that) is refused rather than half-renamed.
#
# NAMES. Installed as `scottapp-<name>'. User scope is shared by every
# repository on the machine, and `feature-builder' / `pr-integrator' read as
# generic roles: a session in some other repo would pick them by name and run
# ScottApp's procedure (its Gherkin layout, its gate, its CLAUDE.md) against the
# wrong codebase. The prefix puts the scope in the name the dispatcher chooses
# by. It also keeps them distinct from the project copies: inside the checkout
# both `feature-builder' (project) and `scottapp-feature-builder' (user) are
# listed, and they are the same text from different refs -- the project one is
# the working tree, this one is `ref'. The renamed copy keeps the repo guard's
# invariant: its `name' is its filename.
#
# THE PREAMBLE. Every agent says "`CLAUDE.md` at the repo root is the rulebook".
# Dispatched from C:\Users\<winuser> there is no repo root, so the installed copy
# gains a short generated block saying where the checkout is, from both sides of
# the WSL boundary. The body below it is byte-for-byte the repository's.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.scottappAgents;

  # Where the rendering lives. Outside ~/.claude on purpose: that directory is
  # what Claude Code scans, and a half-written temp file must never be in it.
  stateDir = "${config.xdg.stateHome}/scottapp-agents";

  installed = name: "scottapp-${name}.md";

  # The checkout as a Windows session spells it. Derived, not configured, from
  # the same distro name the bridge already declares for this boundary.
  winCheckout =
    "\\\\wsl.localhost\\${config.my.windowsBridge.wslDistro}"
    + lib.replaceStrings ["/"] ["\\"] cfg.checkout;

  render = pkgs.writeShellApplication {
    name = "scottapp-agents-render";
    runtimeInputs = [pkgs.git pkgs.coreutils pkgs.gawk pkgs.diffutils];
    text = ''
      # scottapp-agents-render CHECKOUT REF OUTDIR WIN_CHECKOUT NAME...
      #
      # Exit 0: every NAME rendered (or already current). Exit 1: at least one
      # was not, and says why; its previous rendering, if any, is untouched.
      # A missing checkout or ref is exit 0 with a message: that is a machine
      # without ScottApp on it, not an error in this configuration.
      checkout=$1 ref=$2 outdir=$3 wincheckout=$4
      shift 4

      if ! git -C "$checkout" rev-parse --git-dir > /dev/null 2>&1; then
        echo "scottapp-agents: $checkout is not a git checkout; installed agents left as they are." >&2
        echo "                 Set my.scottappAgents.checkout if ScottApp moved." >&2
        exit 0
      fi
      if ! rev=$(git -C "$checkout" rev-parse --verify --quiet "$ref^{commit}"); then
        echo "scottapp-agents: $checkout has no $ref; installed agents left as they are." >&2
        exit 0
      fi

      mkdir -p "$outdir"
      status=0
      for name in "$@"; do
        src=".claude/agents/$name.md"
        dest="$outdir/scottapp-$name.md"

        if ! body=$(git -C "$checkout" show "$rev:$src" 2> /dev/null); then
          echo "scottapp-agents: $ref has no $src; $dest left as it is." >&2
          status=1
          continue
        fi
        # The last commit that touched THIS file, not the tip of the ref: the
        # preamble then changes only when the agent does, so an unrelated merge
        # to ScottApp does not rewrite every installed copy.
        last=$(git -C "$checkout" log -1 --format=%h "$rev" -- "$src")

        # Passed through the environment, not awk -v: -v interprets backslash
        # escapes, and the Windows path is made of backslashes.
        PREAMBLE=$(printf '\n%s\n%s\n%s\n' \
          "> **Installed copy.** ScottApp's \`$src\` as of commit $last on \`$ref\`, installed at user scope as \`scottapp-$name\` by home-manager (\`modules/claude-scottapp-agents.nix\`). Change the original in the repo, not this file." \
          ">" \
          "> **Where the repo is.** \"The repo\", \"the repo root\" and \`CLAUDE.md\` below refer to the ScottApp checkout at \`$checkout\` in WSL (\`$wincheckout\` from Windows), whatever directory you were started in. Read its \`CLAUDE.md\` first, and run the repo's commands inside WSL, in that checkout or in the worktree your brief names.")
        export PREAMBLE

        tmp=$(mktemp "$outdir/.render.XXXXXX")
        chmod 644 "$tmp" # not mktemp's 0600: same mode as the other agent files
        # Front matter must open the file, close, and carry exactly one
        # `name: <filename>' line; anything else is refused, not guessed at.
        if ! printf '%s\n' "$body" | awk -v name="$name" '
          BEGIN { infm = 1 }
          NR == 1 { if ($0 != "---") exit 2; print; next }
          infm && $0 == "---" { infm = 0; closed = 1; print; print ENVIRON["PREAMBLE"]; next }
          infm && $0 == "name: " name { $0 = "name: scottapp-" name; renamed++ }
          { print }
          END { if (!closed || renamed != 1) exit 2 }
        ' > "$tmp"; then
          rm -f "$tmp"
          echo "scottapp-agents: $src at $ref does not open with front matter naming it '$name'; $dest left as it is." >&2
          status=1
          continue
        fi

        if [ -e "$dest" ] && cmp -s "$tmp" "$dest"; then
          rm -f "$tmp"
        else
          mv -f "$tmp" "$dest"
          echo "scottapp-agents: rendered scottapp-$name from $ref ($last)"
        fi
      done
      exit "$status"
    '';
  };
in {
  options.my.scottappAgents = {
    enable =
      lib.mkEnableOption "ScottApp's project subagents at user scope, rendered from its checkout";

    checkout = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/scratch/ScottApp";
      description = ''
        The ScottApp checkout to read the agents from, as an absolute WSL path.
        Read at activation, never at evaluation: the repository is private and
        this flake is evaluated by public CI. Also written into each agent's
        preamble as where "the repo" is.
      '';
    };

    ref = lib.mkOption {
      type = lib.types.str;
      default = "origin/main";
      description = ''
        The committed ref the agents are read from. A ref rather than the
        working tree, so an uncommitted or unmerged edit in the checkout never
        becomes every session's agent.
      '';
    };

    agents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["feature-builder" "pr-integrator" "coverage-raiser"];
      description = ''
        Agent file stems under .claude/agents/ in the repository; each installs
        as scottapp-<stem>. Listed rather than discovered because the Windows
        side's file set is fixed at evaluation time. It matches the set the
        repository's own guard pins, so a fourth agent there is a one-line
        change here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [render];

      # A link to the rendering, owned by home-manager so that disabling the
      # module removes it. Until the first activation renders anything the link
      # dangles, which Claude Code skips; that is the "checkout absent" case.
      file = lib.listToAttrs (map (name: {
          name = ".claude/agents/${installed name}";
          value.source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/${installed name}";
        })
        cfg.agents);

      # Before windowsBridge, which copies the rendering to Windows.
      activation.scottappAgents = lib.hm.dag.entryBetween ["windowsBridge"] ["writeBoundary"] ''
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          echo "scottapp-agents: dry run; would render ${toString (lib.length cfg.agents)} agent(s) from ${cfg.checkout} at ${cfg.ref}"
        elif ! ${render}/bin/scottapp-agents-render ${lib.escapeShellArgs ([cfg.checkout cfg.ref stateDir winCheckout] ++ cfg.agents)}; then
          echo "scottapp-agents: not every agent was rendered (see above); earlier renderings, if any, stay installed." >&2
        fi
      '';
    };

    # The second consumer of the same rendering, like claude-skills' bundle.
    # `source' rather than `text': the content does not exist at evaluation.
    my.windowsBridge.files = lib.listToAttrs (map (name: {
        name = "claude-agents-${lib.replaceStrings ["."] ["-"] (installed name)}";
        value = {
          target = ".claude/agents/${installed name}";
          mode = "own";
          source = "${stateDir}/${installed name}";
        };
      })
      cfg.agents);
  };
}
