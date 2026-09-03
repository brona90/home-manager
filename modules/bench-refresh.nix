# The Bench refreshes itself, because a page about a machine's state that is
# only correct on the day someone deployed it is worse than no page.
#
# WHY THIS RUNS HERE AND NOT IN CI. `dist-bench/bench.json' is a scan of this
# box. On a GitHub runner the same build produces a valid, fully gated document
# describing an empty machine -- so the machine has to scan, gate and deploy.
# github.com/brona90/bench says the same thing in its Makefile; this module is
# the other half of that decision.
#
# THREE THINGS THIS FILE EXISTS TO GET RIGHT, each measured on 2026-09-02
# rather than assumed:
#
# 1. A `systemd --user' unit does NOT get the nix profile. Its PATH is
#    /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin, in which
#    `emacs', `node', `npx' and `jq' are all NOT FOUND and `make' and `git'
#    resolve only to the Debian copies. Hence writeShellApplication with
#    explicit runtimeInputs rather than a bare ExecStart -- the same reason
#    modules/claude-kg wraps kg-snapshot.
#
# 2. `wrangler' is not installed on this machine. Every Cloudflare deploy so
#    far has gone through the `npx wrangler' fallback in modules/sops.nix,
#    which re-resolves against the npm registry on EVERY invocation: 83 seconds
#    warm, and it floated to 4.128.0 while this flake pins 4.126.0. A scheduled
#    deploy is the last place a tool should change underneath you, so this
#    takes wrangler from nixpkgs. Putting it on PATH as well is what finally
#    lets the sops wrapper take its fast branch -- that wrapper's
#    `command -v wrangler' test has been false since the day it was written.
#
# 3. CLOUDFLARE_API_TOKEN is scoped to ONE invocation, never exported. That is
#    modules/sops.nix's rule and its reasoning is set out there: an exported
#    token is inherited by every child for the life of the process and lands in
#    core dumps and /proc, which trades a 0600 file for a much broader
#    exposure. This file obeys it.
#
# COST, measured end to end rather than added up from parts. A full run --
# scan, gate, upload, deploy -- took **341 seconds**. The parts are `make
# bench' 177s (46 checkouts walked, including the bounded disk pass), `make
# bench-check' 6s, and the rest is wrangler: even the pinned binary spends the
# better part of a minute starting before it uploads anything.
#
# At the hourly default that is a ~9.5% duty cycle, not the ~5% an estimate
# from the first two numbers suggests. It is a real tax on a machine doing
# other work, and it is stated here rather than discovered later.
#
# `diskBudgetSeconds' is the dial, and setting it to 0 takes ~90s off. What it
# bounds is the deep `du' pass; the document then SAYS the pass was cut off,
# rather than presenting the first few directories it happened to reach as the
# largest. That honesty is the whole reason the budget exists.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.benchRefresh;

  refresh = pkgs.writeShellApplication {
    name = "bench-refresh";
    runtimeInputs = [
      cfg.emacsPackage
      pkgs.gnumake
      pkgs.git
      pkgs.wrangler
      pkgs.coreutils
    ];
    text = ''
      repo=${lib.escapeShellArg cfg.repo}
      token=${lib.escapeShellArg cfg.tokenFile}

      # Refuse early and legibly. sops-nix decrypts into a tmpfs under
      # /run/user/$UID, so an empty file here means activation has not run in
      # this boot -- not that the secret is gone.
      if [ ! -s "$token" ]; then
        echo "bench-refresh: no decrypted token at $token" >&2
        echo "bench-refresh: run hms, or check sops-nix activation" >&2
        exit 1
      fi

      if [ ! -d "$repo/.git" ]; then
        echo "bench-refresh: $repo is not a checkout" >&2
        exit 1
      fi

      # Say what is about to be scanned. The Bench is a claim about this
      # machine at an instant, so the log has to name that instant's inputs --
      # including a dirty tree, because the page is built from the working
      # copy and not from HEAD.
      head=$(git -C "$repo" rev-parse --short HEAD)
      dirty=$(git -C "$repo" status --porcelain | wc -l)
      echo "bench-refresh: $repo at $head, $dirty uncommitted path(s)"

      # BUILD. Scans this machine; read-only about it by construction.
      BENCH_DISK_BUDGET=${toString cfg.diskBudgetSeconds} \
        make -C "$repo" bench

      # GATE. Deliberately a separate invocation rather than folded into the
      # build with `&&': bench-check does not depend on bench precisely so that
      # it reads dist-bench/ as it stands. If it fails, NOTHING is published --
      # a page that has stopped agreeing with the document beside it is worse
      # than a stale one, because he would believe it.
      make -C "$repo" bench-check

      if [ ! -s "$repo/dist-bench/index.html" ]; then
        echo "bench-refresh: gate passed but dist-bench/index.html is missing" >&2
        exit 1
      fi

      # DEPLOY from a directory that is not a checkout. `wrangler pages deploy'
      # compiles a functions/ directory found in its WORKING directory, not in
      # the directory being uploaded; running it inside a repository is how a
      # dashboard's write path gets compiled onto the wrong project. This
      # repository has no functions/ today, and this line is what keeps that
      # from mattering if one ever appears.
      workdir=$(mktemp -d)
      trap 'rm -rf "$workdir"' EXIT
      cd "$workdir"

      # CLOUDFLARE_ACCOUNT_ID is not decoration. Without it wrangler tries to
      # enumerate the accounts the token can see, which this token cannot do --
      # it fails with "Failed to automatically retrieve account IDs" and
      # suggests `wrangler login', which is precisely the 23-scope OAuth grant
      # modules/sops.nix exists to avoid. Supplying the id is the narrow fix;
      # widening the token is not.
      CLOUDFLARE_API_TOKEN="$(cat "$token")" \
      CLOUDFLARE_ACCOUNT_ID=${lib.escapeShellArg cfg.accountId} \
        wrangler pages deploy "$repo/dist-bench" \
        --project-name ${lib.escapeShellArg cfg.projectName} \
        --branch ${lib.escapeShellArg cfg.branch} \
        --commit-dirty=true

      echo "bench-refresh: published $head"
    '';
  };
in {
  options.my.benchRefresh = {
    enable = lib.mkEnableOption "the Bench refreshing and republishing itself on a timer";

    repo = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/bench";
      description = ''
        The github.com/brona90/bench checkout to build from. The page is built
        from the WORKING COPY, not from HEAD, so local edits appear on the site
        before they are committed.
      '';
    };

    accountId = lib.mkOption {
      type = lib.types.str;
      description = ''
        The Cloudflare account the Pages project lives in. Required: the scoped
        token cannot list accounts, so wrangler cannot discover this.

        Deliberately NOT a sops secret. It is an identifier, not a credential --
        it is useless without the token, it already sits in plaintext in
        ~/.config/.wrangler/logs, and adding a key means rewriting
        secrets.yaml, the one file on this machine with no break-glass
        recipient. That is a catastrophic downside for a cosmetic gain. It
        lives in home/hosts/wsl.nix instead, beside machine identifiers that
        are considerably more sensitive than this one.
      '';
    };

    projectName = lib.mkOption {
      type = lib.types.str;
      default = "bench";
      description = ''
        The Cloudflare Pages project. Its subdomain is ASSIGNED, not derived
        from this name -- `bench' answers on bench-6v5.pages.dev.
      '';
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = ''
        The Pages branch to deploy to. Must equal the project's
        production_branch, or the deploy becomes a preview that the custom
        domain never serves.
      '';
    };

    diskBudgetSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 90;
      description = ''
        Seconds allowed for the deep disk pass, passed as BENCH_DISK_BUDGET. A
        full pass over this home directory took 41m26s when it was measured, so
        the pass is normally cut off and the document says so. 0 skips it and
        keeps only the exact, instant `df' figures.
      '';
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = ''
        systemd OnCalendar expression. A full run was measured at 341s --
        scan, gate, upload and deploy -- so hourly is about a 9.5% duty
        cycle. Lengthen this, or drop diskBudgetSeconds to 0, if that is
        too much of the machine.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/sops-nix/secrets/cloudflare_orrery_token";
      description = ''
        The scoped Cloudflare token, as decrypted by modules/sops.nix. Read
        into one command's environment and never exported. If a deploy fails on
        permissions that is the token being correctly narrow -- widen it
        deliberately, do not fall back to `wrangler login'.
      '';
    };

    emacsPackage = lib.mkOption {
      type = lib.types.package;
      default = config.my.emacs.package;
      defaultText = lib.literalExpression "config.my.emacs.package";
      description = ''
        Which Emacs reads the Org. This must be the one a human gets, and there
        is deliberately NO `pkgs.emacs' fallback the way modules/orrery-mcp.nix
        has one. That module can take any Emacs because nothing it parses
        depends on the Org version; this one cannot. Org 9.8 requires
        whitespace before a headline's tag chain and 9.7 does not, taking the
        longest legal suffix instead -- so the same document yields different
        tag counts depending on the binary, and both pass the `toolchain' gate,
        which only refuses below 9.7. A fallback here would buy an evaluable
        config at the price of a page that is quietly wrong. The assertion
        below is the honest form of that dependency.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.emacs.enable;
        message = ''
          my.benchRefresh.enable requires my.emacs.enable: the Bench is built by
          parsing Org, and the Emacs that does it has to be the one this flake
          builds. See my.benchRefresh.emacsPackage for why there is no fallback.
        '';
      }
    ];

    # wrangler lands on PATH here rather than in modules/dev-tools.nix because
    # this module is the only thing on the machine that needs it. The side
    # effect is the point, though: the `wrangler' function in modules/sops.nix
    # tests `command -v wrangler' and has been taking its `npx' branch since the
    # day it was written, because nothing ever put one there.
    home.packages = [refresh pkgs.wrangler];

    systemd.user.services.bench-refresh = {
      Unit.Description = "Rebuild the Bench from this machine and publish it";
      Service = {
        Type = "oneshot";
        ExecStart = "${refresh}/bin/bench-refresh";
      };
    };

    systemd.user.timers.bench-refresh = {
      Unit.Description = "Refresh bench.fosterthecode.com";
      Timer = {
        OnCalendar = cfg.onCalendar;
        # A missed run catches up: nothing starts WSL when Windows boots, so
        # this distro is regularly down across a scheduled time.
        Persistent = true;
        # Do not land on the hour alongside everything else on the machine.
        RandomizedDelaySec = "5m";
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
