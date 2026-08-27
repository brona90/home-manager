# Home Manager Configuration

A reproducible, cross-platform development environment using [Nix](https://nixos.org/) flakes.

## What's Included

| Tool | Description |
|------|-------------|
| [Emacs](modules/emacs/vanilla) | Hand-built Emacs 30 config — no distribution, an explicit Nix package list, evil + an `SPC` leader, org/org-gcal, Claude Code integration, LilyPond. Reached as `em` / `emt`. Replaced Doom Emacs; see [DESIGN.md](modules/emacs/vanilla/DESIGN.md) for what it does and why, and [RETIRING-DOOM.md](modules/emacs/RETIRING-DOOM.md) for the leftovers a human has to clear. |
| [tmux + tmux-helper](modules/tmux-helper) | Helper-driven tmux config: 50 keybinds, 25 themes (`prefix T` to cycle), fzf popup pickers (`prefix s/w/./P`), SSH-aware status bar, smart-status indicators (git branch / nix-shell / active-LLM), copy-mode `o` opens selection in emacsclient. Replaces the 94 KB gpakosz config with a few hundred lines of native tmux + a one-shot Go binary (~2,100 LOC). |
| [Oh My Zsh](https://ohmyz.sh/) | Zsh framework with plugins: `git`, `z`, `zsh-fast-syntax-highlighting`, `zsh-history-substring-search` |
| [Starship](https://starship.rs/) | Fast, customizable shell prompt |
| [mise](https://mise.jdx.dev/) | Polyglot runtime manager. Used **per-project only** via `direnv use_mise` -- the global zsh integration is intentionally off (5+ s/prompt cost on WSL). Globally needed runtimes live in nixpkgs (`home.packages`). |
| [btop](https://github.com/aristocratos/btop) | Resource monitor with TUI |
| [dev toolchain](modules/dev-tools.nix) | `my.devTools.enable` — compilers (gcc/cmake/make/pkg-config), formatters (alejandra, stylua, black, isort, prettier, gofumpt, shfmt), linters, debuggers, `lazygit`, `delta`, and the VictorMono Nerd Font on Linux. **Not a safe thing to disable:** Emacs compiles vterm and treesit grammars at runtime with the compilers in here. Language servers are *not* here — they live beside the config that hooks them, in `modules/emacs/default.nix`. |
| [fzf](https://github.com/junegunn/fzf) | Fuzzy finder |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast grep replacement |
| [fd](https://github.com/sharkdp/fd) | Fast find replacement |
| [bat](https://github.com/sharkdp/bat) | Cat with syntax highlighting |
| [direnv](https://direnv.net/) | Per-directory environment variables |
| [sops-nix](https://github.com/Mic92/sops-nix) | Encrypted secrets management with [age](https://github.com/FiloSottile/age) |

## Concepts

**[Nix Flakes](https://nixos.wiki/wiki/Flakes)** — A pure, reproducible way to manage Nix projects with locked dependencies. Think `package-lock.json` but for your entire system.

**[Home Manager](https://github.com/nix-community/home-manager)** — Manages user dotfiles and packages declaratively. Instead of manually editing `~/.zshrc`, you define it in Nix and rebuild.

**Modules** — Reusable configuration units. Each tool (zsh, git, emacs) has its own module in `modules/` with options you can enable/configure.

## Quick Start

```bash
# Bootstrap on fresh system (interactive - prompts for username)
# Works piped (prompts read from /dev/tty); process substitution also works:
#   bash <(curl -fsSL https://raw.githubusercontent.com/brona90/home-manager/master/bootstrap.sh)
curl -fsSL https://raw.githubusercontent.com/brona90/home-manager/master/bootstrap.sh | bash

# Or if already have nix and repo cloned:
home-manager switch --flake "$HOME/.config/home-manager#USERNAME@SYSTEM" -b backup
```

Bootstrap requires Nix to be installed first (it prints the [Determinate installer](https://install.determinate.systems) command if missing) and uses `sudo` once to add you to Nix `trusted-users`.

## Forking This Repo

This repo is designed to be easily forked:

1. **Fork on GitHub**

2. **Update `config.nix`:**
   ```nix
   {
     repo = {
       owner = "your-github-username";
       name = "home-manager";
       dockerHubUser = "your-dockerhub-username";  # or same as owner
       cachixCache = "your-cachix-cache";          # optional
       cachixPublicKey = "your-cache.cachix.org-1:..."; # from app.cachix.org → Settings
     };
     users = [
       { username = "yourusername"; systems = [ "x86_64-linux" ]; }
     ];
     git = {
       userName = "Your Name";
       userEmail = "your@email.com";
       signingKey = "YOUR_GPG_KEY_ID";  # GPG key for commit signing
     };
   }
   ```

3. **Run bootstrap** (it will prompt for your fork URL)

4. **(Optional) Keep personal git identity out of git** — copy `config.local.nix.example` to `config.local.nix` (gitignored) and put your `userName`, `userEmail`, and `signingKey` there instead of `config.nix`.

5. **(Optional) Configure CI** - See [.github/SETUP.md](.github/SETUP.md)

## Commands

### General

| Command | Description |
|---------|-------------|
| `hms`   | Home Manager switch (rebuild config) |
| `hmn`   | `home-manager news` for the same flake — the release notes for what changed under you |
| `nrs`   | NixOS rebuild switch (WSL host only — defined in `home/hosts/wsl.nix`) |
| `em`    | Emacs client (GUI frame, TTY when there is no display). Starts the daemon if it is not answering. |
| `emt`   | Same, always a terminal frame |
| `emacs-doctor` | Inspect/reset/monitor the Emacs daemon + WSL health (`status`, `reset`/`fix`, `gui-probe`, `watch`, `version`) — Linux only |
| `terminal` | Run the dev Docker image (`modules/docker-terminal.nix`). Aliases: `term-clean` = plain `terminal`, an ephemeral container; `term-persist` = `--persistent`; `term-here` = `--workspace .`, mounting the cwd |
| `dev-disk` | Show disk usage for Nix, Docker, mise, etc. |
| `dev-clean` | Interactive cleanup of all dev tools |

### Nix (n = nix)

| Command | Description |
|---------|-------------|
| `nfu`   | Nix flake update |
| `ncg`   | Nix collect garbage (basic) |
| `ncgd`  | Nix collect garbage + delete old generations |
| `nco`   | Nix store optimise (deduplicate) |
| `nsc`   | Nix store clean (gc -d + optimise) |

### Docker (d = docker)

| Command | Description |
|---------|-------------|
| `dps`   | Docker ps |
| `dpsa`  | Docker ps -a |
| `di`    | Docker images |
| `dcp`   | Docker clean prune (unused containers/networks) |
| `dcpa`  | Docker clean prune all (+ unused images) |
| `dcpv`  | Docker clean prune volumes |
| `dcpb`  | Docker clean prune builder cache |
| `dca`   | Docker clean all (everything) |

### Mise (m = mise)

| Command | Description |
|---------|-------------|
| `mcp`   | Mise clean prune (remove unused versions) |
| `mcc`   | Mise cache clear |
| `mca`   | Mise clean all (prune + cache) |

### Cache

| Command | Description |
|---------|-------------|
| `ccc`   | Clear ~/.cache (careful!) |

### Git (g = git)

| Command | Description |
|---------|-------------|
| `gs`    | git status |
| `ga`    | git add -A |
| `gd`    | git diff |
| `gl`    | git log (graph) |
| `gla`   | git log --all (graph) |
| `gco`   | git checkout |
| `gnb`   | git checkout -b (new branch) |
| `gpl`   | git pull |
| `gf`    | git fetch |
| `gb`    | git branch |
| `gm`    | git merge |
| `gr`    | git remote -v |

### GPG / YubiKey (WSL)

| Command | Description |
|---------|-------------|
| `gpg-restart` | Reset the Windows Gpg4win bridge and bridge service (use after reinserting YubiKey) |

### Secrets

| Command | Description |
|---------|-------------|
| `github-token` | Print GitHub token |
| `dockerhub-token` | Print Docker Hub token |

## Structure

```
.
├── flake.nix              # Main entry point, defines inputs and outputs
├── flake.lock             # Pinned inputs (bumped weekly by update-flake.yml)
├── config.nix             # User & repo configuration (edit this!)
├── config.local.nix.example  # Template for gitignored local git identity/overrides
├── bootstrap.sh           # Fresh-machine installer (Nix check, sops setup, first switch)
├── CLAUDE.md              # Repo-scope instructions for Claude Code
├── .mcp.json              # Project-scope MCP server registrations
├── .envrc                 # `use flake` — see "Dev shell and git hooks"
├── .sops.yaml             # age public keys (safe to commit)
├── home/                  # Home Manager profiles
│   ├── common.nix         # Shared across all systems
│   ├── linux.nix          # Linux-specific (platform-generic)
│   ├── darwin.nix         # macOS-specific (platform-generic + shared brew-sync)
│   └── hosts/             # Machine-specific layers (mapped via users.*.hosts in config.nix)
│       ├── wsl.nix        # gfoster's WSL box: build farm, GPG bridge, /mnt/c aliases
│       ├── personal-mac.nix  # Personal MacBooks: Homebrew lists
│       └── corp-mac.nix   # Corporate Mac: Homebrew lists + Zscaler bypass
├── hosts/                 # NixOS configurations (unrelated to home/hosts/)
│   ├── common/            # Shared NixOS settings
│   └── wsl/               # WSL-specific config
├── modules/               # Reusable Home Manager modules
│   ├── zsh.nix            # Shell config with oh-my-zsh, starship, mise, direnv
│   ├── git.nix            # Git + GPG signing
│   ├── gpg.nix            # GPG agent + YubiKey bridge (forwardToWindows)
│   ├── btop.nix           # System monitor
│   ├── dev-tools.nix      # Compilers, formatters, linters, debuggers, CLI utilities
│   ├── sops.nix           # Secrets management (sops-nix + age)
│   ├── docker-terminal.nix  # `terminal` wrapper for the Docker dev image
│   ├── displayplacer.nix  # macOS display layout (darwin only)
│   ├── zscaler-bypass.nix # Route-only Zscaler bypass (darwin only)
│   ├── claude-code.nix    # Claude Code CLI settings, hooks, MCP server merging
│   ├── claude-skills.nix  # User-scope skills + subagents ->
│   │   └── claude-skills/ #   skills/{nix-home-manager,org-elisp,wsl-interop},
│   │                      #   agents/{consumer-sweeper,elisp-batch-engineer,nix-module-author}
│   ├── claude-specflow.nix  # /specflow scaffolder ->
│   │   └── claude-specflow/ #   commands/, templates/specflow/{agents,commands,hooks,rules},
│   │                        #   tests/branch-policy-matrix.sh (guarded by branch-policy-hook)
│   ├── claude-kg/         # Local knowledge-graph MCP server + Qdrant (my.claudeKg)
│   │                      #   default.nix, package.nix, src/, README.md
│   ├── searxng/           # Local SearXNG metasearch + web_search MCP (my.searxng)
│   │                      #   default.nix, package.nix, settings.yml, src/, README.md
│   ├── orrery-mcp.nix     # MCP server for the Orrery dashboard (source NOT vendored here)
│   ├── emacs-mcp.nix      # Emacs MCP server module
│   ├── emacs-mcp-server.py  # MCP stdio server bridging Claude Code -> emacsclient
│   ├── emacs/             # Emacs
│   │   ├── default.nix    # the package, the daemon unit, language servers, em/emt
│   │   ├── RETIRING-DOOM.md  # leftovers a human must clear after the switch
│   │   └── vanilla/       # Hand-built Emacs 30: package.nix (explicit package
│   │                      #   list) + config/{early-init,init}.el, config/lisp/*.el
│   │                      #   + DESIGN.md, verify.sh/verify.el (the gate)
│   ├── emacs-doctor/      # Go CLI: daemon health, reset, gui-probe, watch (Linux only)
│   ├── tmux/              # helper-driven tmux conf + 25 theme palettes (themes.nix)
│   │                      #   + GRADUATION.md (the parallel-socket trial pattern)
│   ├── tmux-helper/       # Go helper binary (status, clipboard, theme, navigate, ...)
│   └── scripts/
│       └── gpg-win-bridge.py  # WSL->Gpg4win Assuan proxy
├── checks/                # The `nix flake check` guard set — one file per concern
│   ├── default.nix        # Merges them; documents the interface a guard file is handed
│   ├── branch-policy.nix  # branch-policy-hook
│   ├── claude-settings.nix  # claude-settings-guards
│   ├── dev-shell.nix      # devshell-stays-light, install-hooks-installs-hooks
│   ├── docker-terminal.nix  # docker-terminal-no-ssh-mount
│   ├── emacs-gate.nix     # ci-emacs-gate
│   ├── lint-tools.nix     # lint-tools-pinned
│   ├── shell-scripts.nix  # background-jobs-close-fds, devshell-hook-lint
│   └── tmux-helper.nix    # tmux-helper-build, tmux-helper-vet (builds, not guards)
├── secrets/               # Encrypted secrets (safe to commit)
│   ├── secrets.yaml
│   └── README.md          # The key structure, as a commented example
├── lib/                   # Helper functions
│   ├── lint-tools.nix     # the pinned linter set (.#lint-tools) every gate uses
│   ├── docker-image.nix   # Docker image builder (full + slim profiles)
│   ├── docker-test-app.nix
│   ├── dev-shell.nix      # devShell + hook bootstrap (see "Dev shell and git hooks")
│   ├── dev-shell-hook.sh  # the shellHook — runs on every `cd`, must stay cheap
│   ├── install-hooks.sh   # body of `nix run .#install-hooks`
│   ├── warm-direnv.sh     # post-merge/checkout/rewrite background cache warm
│   ├── link-pc-config.sh  # gives a new worktree its .pre-commit-config.yaml
│   └── pre-commit-hooks.nix  # the hook set handed to git-hooks.nix
└── .github/
    ├── SETUP.md           # CI setup: required secrets, status checks
    ├── dependabot.yml     # Action version bumps
    ├── workflows/         # CI/CD
    │   ├── ci.yml             # Main pipeline
    │   ├── update-flake.yml   # Weekly flake.lock update PRs
    │   └── validate.yml       # NixOS/Darwin validation (manual, weekly, or on flake/hosts changes)
    └── actions/
        └── nix-build-retry/   # composite action: retry a build set on transient
                               #   network failures (eval-darwin, build-home)
```

## Dev shell and git hooks

`.envrc` is `use flake`, so every `cd` into this repo evaluates
`devShells.default`. nix-direnv caches that, but the cache is keyed on
`flake.nix`/`flake.lock` — and `flake.lock` moves every week on its own, via
`update-flake.yml`. Anything the devShell mentions therefore gets re-evaluated,
from scratch, at an interactive prompt, roughly weekly.

Measured on x86_64-linux with a warm store (`nix eval --no-eval-cache`, one run
per line so the figures are comparable — so this is evaluation alone):

| evaluated | time |
| --- | --- |
| `packages.tmux-helper` — the bare flake-load floor | ~8 s |
| `packages.lint-tools` — the linters alone | ~31 s |
| the old `devShells.default` — git-hooks **and** the linters | ~50 s |
| this `devShells.default` | ~7 s |

Read the excess over the floor: the linters are ~22 s and git-hooks ~19 s, and
they overlap. Neither one is *the* cost, so removing only one would have left
about half the problem. `devShells.default` therefore contains **neither**. It
is a bare `mkShell` whose shellHook is plain shell against the filesystem, and
the expensive work lives in an app:

```bash
nix run .#install-hooks     # installs .git/hooks/* and the linter bundle
```

The hooks are still installed automatically — the shellHook runs that app for
you. What changed is *when*:

- **No working `pre-commit` hook** (fresh clone, or a `nix-collect-garbage`
  left it dangling): the shellHook installs it in the **foreground** and the
  prompt waits. A shell that returned fast while leaving commits unlinted would
  be a worse bug than a slow shell.
- **Hooks work but were built against an older `flake.lock`**: refreshed in the
  **background**, lock-guarded so repeated `cd`s cannot stack up copies.

`nix run .#install-hooks` also installs `post-merge`, `post-checkout` and
`post-rewrite` hooks. They do two things: give the worktree a
`.pre-commit-config.yaml` if it has not got one (see below), and refill the
direnv cache in the background, so a `git pull` that moves the lock does not
leave the refill to ambush your next `cd`. They never delay the git command and
print nothing when they work.

The linters are not on `PATH` directly. `install-hooks` materialises
`packages.lint-tools` at `.direnv/lint-tools` (with a GC root) and the
shellHook puts `.direnv/lint-tools/bin` on `PATH`, which is what keeps
`statix`/`alejandra` typeable without the devShell having to evaluate them.

Net effect on the number you actually feel — full cold `direnv export bash`,
interleaved against a worktree of `master` on the same machine, with nix's eval
cache cleared before each run (a real `flake.lock` bump changes the lock's
*content*, which gives the flake a new identity and a cold eval cache;
`touch`ing the lock does not, and measurements that only `touch` it will
cheerfully report 6 s for the unchanged shell):

| | cold | warm |
| --- | --- | --- |
| `master` | 54.8 s, 57.9 s | ~0.5 s |
| this branch | 12.2 s, 10.2 s | ~0.7 s |

This was not a substituter miss: `nix build --dry-run` against an empty store
says the old devShell needs 107 paths fetched (233 MiB) and 2 derivations built
locally, and this one 45 paths (122 MiB) and 1. The caches have it; the cost
was evaluation plus download, so adding caching would not have helped.

### These hooks belong to the clone, not to the branch

`.git/hooks` is shared by every worktree. Installing from any one of them
changes how `git` behaves in **all** of them, including worktrees checked out
at commits that predate this arrangement. That is deliberate and safe, because
nothing in the hooks is branch-specific:

- The warm hooks read `.envrc` and `flake.nix` from whichever worktree fired
  them, so a worktree on an older commit simply gets its own devShell warmed.
  Nothing assumes the split described above.
- They exit 0 having done nothing when there is no `.envrc`, when the directory
  was never `direnv allow`ed, when `nix` is not on `PATH`, and when the
  checkout did not touch `flake.nix`, `flake.lock` or `.envrc`.
- They never delay the git command and print nothing on success.

They are GC-rooted from `.git/hooks/.hm-gcroots/` — the same shared directory
as the hooks themselves. A root under one worktree's `.direnv` would be
shorter-lived than the hook it protects (`direnv prune` or `git worktree
remove` strands it), and a collected script makes every `git checkout` in every
worktree print an exec error. Belt and braces: the hooks test the path before
`exec`ing it, and the devShell notices a collected root and reinstalls.

### A new worktree gets its own `.pre-commit-config.yaml`

`.git/hooks` belongs to the clone, but `.pre-commit-config.yaml` does **not**.
The hook `git-hooks.nix` generates passes a *relative*
`--config=.pre-commit-config.yaml`, which `pre-commit` resolves against the
worktree it was invoked in. So `git worktree add` used to produce a worktree
that the shared `pre-commit` hook fires in and that has no config, and every
commit in it died with:

```
No .pre-commit-config.yaml file was found
- To temporarily silence this, run `PRE_COMMIT_ALLOW_NO_CONFIG=1 git ...`
```

The `post-checkout` hook now links it in at the moment the worktree is created
(`lib/link-pc-config.sh`); the devShell links it too, from the same recorded
path, for the cases `post-checkout` cannot reach. Nothing to do by hand.

**Do not take `pre-commit`'s advice in that message.** Both
`PRE_COMMIT_ALLOW_NO_CONFIG=1` and installing the hook with
`--allow-missing-config` unblock the commit by *skipping every linter*, turning
"this worktree is misconfigured" into "this worktree is not linted", silently. A
blocked commit is recoverable; a quietly unlinted one is not. A `nix flake
check` guard fails the build if the hook is ever installed with
`--allow-missing-config`.

If a worktree ever does end up without one, the fix is:

```bash
nix run .#install-hooks
```

Two consequences worth knowing:

- The config is a JSON file whose every entry is an absolute `/nix/store` path,
  with nothing worktree- or even repo-specific in it, so one copy is shared by
  all worktrees and it is GC-rooted once, in `.git/hooks/.hm-gcroots/`.
- A worktree therefore gets linted by the *installed* hook set, not by its own
  `lib/pre-commit-hooks.nix` — exactly as it already was for the `pre-commit`
  hook itself. Changing the hook set means re-running `install-hooks`; the
  devShell notices on its own, because `lib/pre-commit-hooks.nix` is one of the
  files hashed into the staleness stamp.

`git worktree remove` needs no special handling: the link lives inside the
worktree and goes with it, while the GC root it was made from lives in the
shared git dir and survives.

### `core.hooksPath` is cleared on purpose

Chasing the above turned up a second and worse fault in the same place.
`git-hooks.nix`'s installer finishes by setting `core.hooksPath`, to a value it
deliberately makes *relative* to the working copy it was run from:

```sh
common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
common_dir=${common_dir#$GIT_WC/}                    # "/repo/.git" -> ".git"
git config --local core.hooksPath "$common_dir/hooks"
```

Run from the main checkout, that stores `.git/hooks`. In a **linked worktree**
`.git` is a *file*, not a directory, so `.git/hooks` names nothing — git finds
no hooks there and **every commit in every worktree goes through unlinted, in
silence**. Verified by committing a deliberately misformatted `.nix` file in a
fresh worktree and watching it sail through.

Which of two broken states a clone is in depends only on where `install-hooks`
was last run:

| last run from | `core.hooksPath` | effect in a linked worktree |
| --- | --- | --- |
| the main checkout | `.git/hooks` (relative) | no hooks at all — commits **unlinted**, silently |
| a linked worktree | `/abs/path/.git/hooks` | hooks run — commits **refused**, no config |

`install-hooks` therefore unsets `core.hooksPath` after the upstream installer
has set it. With the config absent, git resolves hooks against the common git
dir by itself, correctly, from the main checkout and from every worktree — and
unlike an absolute value that keeps working if the clone is ever moved. Nothing
is lost: the upstream installer already unsets any pre-existing value before it
runs, because `pre-commit` refuses to install while `core.hooksPath` is set.

The three scripts that need the hooks directory (`install-hooks.sh`,
`link-pc-config.sh`, `dev-shell-hook.sh`) fall back to
`--git-common-dir` + `/hooks`, because `git rev-parse --path-format=absolute
--git-path hooks` *fatals* in a linked worktree while the relative config is
still in place — the state of every clone that has not re-run `install-hooks`
yet. Guards `(g2)` and `(g3)` in `install-hooks-installs-hooks` hold both
halves in place.

To back the whole thing out — the `pre-commit` hook is left alone, since it
predates this and removing it would stop linting commits:

```bash
nix run .#install-hooks -- --uninstall
```

If any of this looks wrong, `nix run .#install-hooks` is always safe to re-run;
the background job's output is in `.git/hooks/.hm-install-hooks.log`. Four
`nix flake check` guards keep the arrangement honest — `devshell-stays-light`,
`install-hooks-installs-hooks`, `background-jobs-close-fds` and
`devshell-hook-lint`.

## Supported Systems

- `x86_64-linux` (Debian, Ubuntu, NixOS, WSL)
- `aarch64-linux` (Raspberry Pi, ARM servers)
- `x86_64-darwin` (Intel Mac) — **pinned, and expiring 2026-12-31.** nixpkgs
  drops this platform then, so `flake.nix` holds it on a separate
  `nixpkgs-26.05-darwin` input with its own home-manager. It gets a bare
  devShell: no git hooks, and no `install-hooks` app. Treat it as a machine
  being kept alive, not a supported target.
- `aarch64-darwin` (Apple Silicon Mac)

## New Machine Setup

**Step 0 — install Nix** (bootstrap checks for it and prints this command if missing):

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Note: bootstrap needs `sudo` once to add your user to Nix `trusted-users` in `/etc/nix/nix.conf` (required for cachix; it warns and asks for confirmation first).

### Option 1: Same age key (share secrets across machines)

```bash
# 1. Run bootstrap
curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash

# 2. When prompted for sops setup, paste your existing age key
# (copy from ~/.config/sops/age/keys.txt on existing machine)

# 3. Done! Secrets will decrypt automatically
```

### Option 2: New age key (per-machine keys)

```bash
# 1. On new machine: run bootstrap, choose to generate new key
curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash

# 2. Bootstrap will show your public key (age1...)

# 3. On existing machine with secrets:
cd ~/.config/home-manager
emt .sops.yaml  # Add new public key
sops updatekeys secrets/secrets.yaml
git add -A && git commit -m "feat(sops): add <machine> key" && git push

# 4. On new machine:
cd ~/.config/home-manager
git pull
hms
```

## Emacs

One Emacs, hand-built: `pkgs.emacs` 30.2 on every platform, an explicit package
list in Nix, and a config that is a set of `.el` files rather than a
distribution. It replaced Doom Emacs after running beside it on a second socket
for four gated phases. The reasoning — every place it deliberately does
something other than the obvious thing — is in
[`modules/emacs/vanilla/DESIGN.md`](modules/emacs/vanilla/DESIGN.md).

| | |
|---|---|
| Built by | `modules/emacs/vanilla/package.nix` (`pkgs.emacs` 30.2) |
| Config lives in | `modules/emacs/vanilla/config/` → linked to `~/.config/emacs` |
| systemd user unit | `emacs` (launchd agent on darwin) |
| Server socket | `$XDG_RUNTIME_DIR/emacs/server` — **the default** |
| Reach it | `em`, `emt`, bare `emacsclient` |
| Restarted by `hms`? | **No** (`X-RestartIfChanged = false`) |
| Try a build without `hms` | `nix run .#emacs-vanilla` |
| Theme | `gruvbox-dark-medium` (upstream `gruvbox-theme`) |
| Gate | `bash modules/emacs/vanilla/verify.sh` |

Only one Emacs package is ever on `PATH`, and that is enforced rather than
assumed: `home.path` is a `buildEnv` with collisions fatal, so a second one is a
hard build failure on `bin/emacs`, `bin/emacsclient`, `bin/ctags` and
`emacs.desktop`. A bare `emacs` or `emacsclient` is therefore unambiguous.

`my.emacs.package` is what every consumer reads — `em`/`emt`, `EDITOR`/`VISUAL`,
`emacs-doctor`, the `emacs` MCP server, and `modules/orrery-mcp.nix` (which uses
it only for `emacs -Q --batch`, where any Emacs would do, to avoid pulling a
second one into the closure). There used to be a `my.emacs.flavor` enum and a
read-only `primaryPackage` resolving it; both went with Doom rather than being
left as an enum with one value. Each of those three call sites carries a note
saying what it would have to do if a second Emacs ever came back.

### `EMACS_SOCKET_NAME`, and why the unit sets it

The `emacs` unit exports `EMACS_SOCKET_NAME=%t/emacs/server`. This is the
mechanism by which a Claude Code session running in a vterm **inside** the
daemon fires its hooks at **that** daemon: Emacs never exports the variable to
its subprocesses — it is read by the `emacsclient` *binary* and by nothing
inside Emacs — so a hook inherits it only because the unit put it there.
`modules/claude-code.nix` runs its hooks as

```sh
emacsclient ${EMACS_SOCKET_NAME:+-s "$EMACS_SOCKET_NAME"} --eval ...
```

With one Emacs the unset fallback is already correct — a bare `emacsclient`
resolves to the only one on `PATH`. The line is set **explicitly anyway**, and
that is the whole argument for it: the fallback stops being correct the moment
anything puts `EMACS_SOCKET_NAME` into the systemd *user manager's*
environment, because units inherit that. One `systemctl --user
import-environment` from a shell where it had been exported by hand is enough,
and it persists until the manager restarts. A unit-level `Environment=`
overrides the inherited environment, so this makes the right answer a guarantee
rather than a coincidence.

`%t` is `$XDG_RUNTIME_DIR`, expanded by systemd when the unit loads, so the
value is an absolute path and does not depend on the hook process having
`XDG_RUNTIME_DIR` set.

### What it does

Each row is one file under `config/lisp/`, and each has a section in
[DESIGN.md](modules/emacs/vanilla/DESIGN.md) recording what it deliberately does
**not** do — the omissions are the part worth reading, because every one of them
is a decision rather than a gap.

| | |
|---|---|
| **Editing** | evil-mode, an `SPC` leader with 23 named prefixes and ~235 named keys, which-key (built into Emacs 30), vertico/consult/marginalia/orderless/embark completion, magit + forge + diff-hl, vundo, avy, envrc, ws-butler |
| **Languages** (`my-lang.el`) | 21 file types. Every one that has a tree-sitter mode in Emacs 30.2 gets a live parser; 17 grammars come from Nix as an explicit list, and five are deliberately absent because no `-ts-mode` exists for them (markdown, LaTeX, Common Lisp, elisp, Fortran are font-lock modes and a grammar would only grow the closure) |
| **LSP** (`my-lang.el`) | eglot, hooked into **17** modes — exactly the ones whose server is actually installed. C, C++, CMake, Fortran and LaTeX get a working major mode and no eglot hook, because a hook with no server behind it logs a failed connection on every `find-file` and teaches you to ignore eglot errors. Three explicit contacts: `taplo` for TOML, a pin to `pyright-langserver` for Python (pyright *and* ruff are installed, so eglot otherwise picks one silently), and `nil` for `nix-ts-mode` |
| **Claude Code** (`my-claude.el`, `claude-diff.el`) | the `claude-code` package on `SPC l` — four session keys and seven diff-review keys. `claude-diff.el` is the two-way review integration: a `modules/claude-code.nix` PermissionRequest hook `emacsclient --eval`s into the daemon and Emacs shows the proposed edit as a real diff you accept or reject. It is required **eagerly**, because `--eval` cannot autoload a function that has no stub |
| **LilyPond** (`my-lilypond.el`) | `.ly`/`.ily` through a casing shim (2.26 renamed `LilyPond-mode` to `lilypond-mode`), a **flymake** backend for lilypond's diagnostics, and async build-on-save that re-renders the PDF. The backend is registered and flymake is deliberately left **off**, so the default is one lilypond process per save rather than two |
| **Org** (`my-org.el`) | agenda, capture, refile, and org-gcal against three calendars with a 30-minute background fetch — see below |
| **Popups** (`my-popups.el`) | `*Help*`, `*Apropos*`, `*eldoc*`, `*info*`, flymake diagnostics, `*Messages*`, `*Warnings*` and `*compilation*` in **one** bottom side window, toggled with `SPC ~`. ~60 lines of `window-sides-slots` and `display-buffer-alist` and **zero packages**; `popper` and `shackle` were both evaluated and rejected |
| **Secrets** (`my-secrets.el`) | the org-gcal OAuth token store, and the argument for why it is a plain `0600` file |

The gate exercises all of it in a **real daemon** — not `emacs --batch`, which
does not load `init.el` at all. It walks the actual leader keymap and asserts
every command it reaches is `fboundp`, opens one real sample file per language
and checks the mode and parser, runs a real `lilypond` over four files and
checks the diagnostics, and displays real buffers on the daemon's frame to
measure the window rules. It has caught real bugs three phases running.

### Configuration Files

| File | Purpose |
|------|---------|
| `modules/emacs/vanilla/package.nix` | The explicit package list, and the derivation that assembles the config |
| `modules/emacs/vanilla/config/early-init.el` | Pre-UI setup; redirects every writable path (`eln-cache`, `custom.el`, auto-save, `recentf`, `transient`) out of `user-emacs-directory` |
| `modules/emacs/vanilla/config/init.el` | Main configuration: UI, theme, completion, evil |
| `modules/emacs/vanilla/config/lisp/*.el` | `my-bindings.el` (the `SPC` leader), `my-lang.el`, `my-org.el`, `my-claude.el`, `claude-diff.el`, `my-lilypond.el`, `my-popups.el`, `my-secrets.el` |
| `lisp/my-nix-paths.el` | **Generated**, not a source file. `package.nix` writes it at build time with the store paths Emacs needs (lilypond and its site-lisp, and friends) and copies it into the config derivation. It is not in git and it is not under `config/lisp/` — do not go looking for it, and do not add it. Changing what it contains means editing the `nixPaths` binding in `package.nix` |
| `modules/emacs/vanilla/verify.sh` + `verify.el` | The gate: lints by exit code, builds, then asks a **real daemon** |
| `modules/emacs/vanilla/DESIGN.md` | Why each of the above does what it does |

`~/.config/emacs/` is an **output**, not a source: `xdg.configFile."emacs"` links
the tree there (`recursive = true`, so real directories are created and Emacs
can still write `custom.el`, `eln-cache/` and friends while every `.el` stays
store-managed). Editing files there is lost on the next `hms` — with one escape
hatch: `my.emacs.manageConfig = false` stops linking and hands the directory to
a working copy, for iterating on `init.el` without an `hms` per keystroke.

### Applying Changes

There is nothing to sync. Every change requires a Home Manager rebuild, and the
daemon is deliberately **not** restarted by it:

```bash
hms

# X-RestartIfChanged = false, so a rebuild can never eat unsaved buffers.
# Pick the new config up explicitly, when you are ready to lose the session:
systemctl --user restart emacs      # Linux with systemd
# Or manually:
emacsclient -e '(kill-emacs)'
em                                  # this restarts the daemon
```

Before pushing a config change, run the gate. It is the only thing that catches
this config's characteristic failure — `package-enable-at-startup` is nil, so a
key can be bound, show a name in the which-key popup, and be **void** when
pressed:

```bash
bash modules/emacs/vanilla/verify.sh
```

### Adding Packages

There is no `package!` and nothing imperative. The package list is an
**explicit, hand-maintained list** in `modules/emacs/vanilla/package.nix`:

```nix
withPkgs = baseEmacs.pkgs.withPackages (epkgs:
  with epkgs; [
    some-package
  ]);
```

Nothing parses the elisp to discover packages: `emacsWithPackagesFromUsePackage`
cannot handle the unicode box-drawing rules this config uses, and a silent
mis-parse is worse than a list someone has to remember to update.

> **The reachability rule — the trap that once shipped six broken keys.**
> Putting a package in that list makes it *available*; it does not make it
> *load*. If its `use-package` form has no autoload keyword — `:commands`,
> `:hook`, `:mode`, `:bind`, `:after` — and no `:demand t`, the package is
> **absent at runtime, not lazily loaded**: none of its commands are ever
> autoloaded, and calling one fails with `void-function`. Bindings that point at
> such a command look perfectly correct in the source. Add the package *and* a
> keyword that makes it reachable, then actually invoke it once.

Then rebuild: `hms`, and run the gate.

**There is no module system**, and that is the point — no flag list to
uncomment. A feature exists only if some file under `config/lisp/` configures it
*and* `package.nix` provides the package, and those two halves are always edited
together.

### Keybindings — the `SPC` leader

evil-mode with an `SPC` leader and a discoverable menu
(`config/lisp/my-bindings.el`): 23 named prefixes and roughly 235 named leader
keys, each showing a human-readable name in the which-key popup — which-key is
built into Emacs 30, so no package is involved.

Two keys worth knowing that are not obvious from the menu:

- **`SPC ~`** — `window-toggle-side-windows`, hide/restore the bottom popup.
  It is one built-in command doing the job of Doom's `+popup/toggle` *and*
  `+popup/restore`, and it round-trips: press it twice and the popup comes back
  where it was, with its mode line still suppressed. (That second half is
  tested, because it was once broken —
  `window-state-get`/`window-state-put` copy a window parameter only if it is
  named in `window-persistent-parameters`, and `mode-line-format` is not there
  by default.)
- **`SPC t f`** — toggle flymake in the current buffer. It is off everywhere by
  default except where eglot turns it on: the LilyPond backend is *registered*
  but not *enabled*, so the default is one lilypond process per save (the
  build, which produces the PDF) rather than two.

The keys follow **Doom's**, because that is where the muscle memory came from,
with about ten **deliberate divergences** — keys where Doom's command does not
exist outside Doom, so the key is kept but the behaviour differs (`SPC c e`,
`SPC c d`, `SPC f D`, `SPC s l`, `SPC m r` and friends). The divergence table
lives in
[`modules/emacs/vanilla/DESIGN.md`](modules/emacs/vanilla/DESIGN.md)
("Deliberate differences from Doom — bindings") and is deliberately not copied
here, so the two cannot drift apart.

### Why This Approach?

Doom Emacs, which this replaced, was already built reproducibly through
nix-doom-emacs-unstraightened rather than through an imperative `doom sync`. The
hand-built config keeps that property by a shorter route: its packages come from
the Emacs package set of the nixpkgs pinned in `flake.lock`
(`baseEmacs.pkgs.withPackages`), named in one explicit list in `package.nix`.
All packages pinned in `flake.lock`, reproducible across machines, no network
access after the build, rollback via previous generations — and no distribution
between the config and Emacs.

Nothing parses the elisp to discover packages, deliberately:
`emacsWithPackagesFromUsePackage` cannot handle the unicode box-drawing rules
this config uses, and a silent mis-parse is worse than a list someone has to
remember to update. That is what the gate is for.

### Org Agenda & Google Calendar (org-gcal)

The org config wires up an agenda + capture workflow and two-way Google
Calendar sync. Agenda files (`inbox.org`, `todo.org`, `projects.org`, and the
`gcal*.org` calendars) live in `~/org/`; capture templates (`SPC X`) drop todos,
notes, and calendar events into the right file, and the TODO lifecycle is
`TODO → NEXT → WAIT → DONE/CANCELLED`. It lives in `config/lisp/my-org.el`.

[`org-gcal`](https://github.com/kidd/org-gcal.el) syncs those `gcal*.org` files
against Google Calendar, from sops-managed OAuth credentials (never in the
repo): `org_gcal/client_id` and `org_gcal/client_secret` are decrypted to
`~/.config/sops-nix/secrets/` on `hms`.

It fetches **in the background**, 90 seconds after the daemon starts and then
every 30 minutes, and an around-advice saves the buffers afterwards — org-gcal
populates them and never writes them, which is what once made a calendar look
like it was not syncing at all. `SPC m G s/f/p` are sync, fetch and post-at-point
by hand.

> That timer was absent for the whole period when a second Emacs ran beside
> Doom, because two daemons on it would write `~/org/gcal*.org` underneath each
> other. One Emacs means one writer. The rule did not disappear, it moved: the
> config gate (`verify.sh`) starts a *third* real daemon, so `my-org.el` sets
> `my/org-gcal-fetch-inhibit` from the environment variable the gate exports,
> and the gate asserts both that the timer exists and that the inhibit is on.

**The OAuth token store is a plain `0600` file**,
`~/.local/state/emacs/oauth2-auto.eld` — not a GPG-encrypted plstore. That is
deliberate and argued at length in
`modules/emacs/vanilla/config/lisp/my-secrets.el`. Doom's store was encrypted to
a dedicated key whose *passphrase-less private half* sat at `0600` on the same
disk, so the encryption was never adding protection over the file mode — and it
cost a certify-capable, always-unlocked key sitting ultimately trusted in the
keyring. Encrypting to the YubiKey key instead is not available while the fetch
has to run unattended; that trade-off is real and was made knowingly, and it is
why the fetch is allowed to be a background timer at all.

That key (`org_gcal/gpg_private_key`) is no longer decrypted or imported by
activation. Deleting it from the keyring and from `secrets.yaml` is manual —
see [`modules/emacs/RETIRING-DOOM.md`](modules/emacs/RETIRING-DOOM.md).

First-time setup (once):

1. Create a Google Cloud OAuth client (type "Desktop app") with the Calendar
   API enabled; add your Google account as a Test user.
2. Store the credentials in sops:
   ```bash
   sops set secrets/secrets.yaml '["org_gcal"]["client_id"]'     '"...id..."'
   sops set secrets/secrets.yaml '["org_gcal"]["client_secret"]' '"...secret..."'
   ```
3. `hms`, then in Emacs run `M-x org-gcal-sync` and complete the browser auth
   once.

`M-x my/oauth2-import-from-plstore` imports a refresh token from a legacy GPG
plstore instead of redoing the browser flow. It was the migration path off
Doom's store; it is kept only as a recovery route, and it stops working once
the passphrase-less key leaves the keyring.

### Troubleshooting Emacs

One user unit, `emacs`, owning `%t/emacs/server`.

```bash
# Check if the daemon is running
systemctl --user status emacs

# View daemon logs
journalctl --user -u emacs -f

# Force restart (this DOES lose unsaved buffers — hms never does it for you)
systemctl --user restart emacs

# Is it actually answering?
emacsclient -e '(emacs-version)'
ls -l "$XDG_RUNTIME_DIR/emacs/"

# Run emacs without a daemon (for debugging)
emacs --debug-init
nix run .#emacs-vanilla           # throwaway foreground build, no daemon,
                                  # no hms, no socket — cannot collide with
                                  # the running one

# Check what packages are installed
nix path-info -rsh $(which emacs) | sort -hk2 | tail -20
```

A leftover `emacs-doom` unit from a generation before Doom was retired is
disabled with `systemctl --user disable --now emacs-doom`; see
[`modules/emacs/RETIRING-DOOM.md`](modules/emacs/RETIRING-DOOM.md).

#### `emacs-doctor` — daemon health & recovery

The daemon is owned by the `emacs` systemd **user** unit, and `emacs-doctor`
diagnoses it (it follows `my.emacs.package` and the default socket). The
failure mode to know about: a stray standalone `emacs --daemon` can grab the
server socket, the managed `--fg-daemon` can then never bind it, and
`Restart=on-failure` relaunches it forever —
pegging a CPU core and making both Emacs *and* every other GUI app feel slow (CPU
starvation, not graphics). Tell-tale: `NRestarts` climbing and `ActiveState=activating`
that never reaches `active`.

`emacs-doctor` (Linux only) inspects and recovers this:

```bash
emacs-doctor status        # daemon state + orphan/socket-squat detection,
                           # plus WSL load, top CPU, GPU/GL health
emacs-doctor reset         # recover to ONE clean systemd-managed daemon.
                           # Refuses if any buffer is unsaved (see below).
emacs-doctor reset --force # same, but discard unsaved changes
emacs-doctor gui-probe -- emacsclient -c   # time a real app's launch→first window
emacs-doctor gui-probe     # no cmd: xeyes X11 round-trip floor + load average
emacs-doctor watch [secs]  # re-run status on an interval (default 5s)
```

GUI launch time on WSL is dominated by system load and one-time per-session
costs (cold fontconfig/GL/GStreamer plugin caches, D-Bus service activation), so
`gui-probe` reports the load average and, given a real command, measures its
actual launch→first-window time rather than a trivial `xeyes` client (which skips
all the toolkit init that makes real apps slow).

`reset` will **not** discard unsaved work — if any file buffer is modified it lists them
and aborts (use `--force` to override). It stops the service, kills orphan daemons,
clears the primary's stale socket (`$XDG_RUNTIME_DIR/emacs/server`), `reset-failed`s,
and starts a single clean daemon.

Every clean-up here names **exactly one file**: the unit's `ExecStartPre` is
`rm -f %t/emacs/server`, never `rm -rf %t/emacs`. That rule was written when
two daemons shared the directory and a recursive remove would have deleted the
other one's *live* socket; there is one daemon again, but `%t/emacs/` is also
where emacsclient keeps per-frame state, and a recursive remove in an
`ExecStartPre` is never the smaller change it looks like.

The safeguards in `modules/emacs/default.nix` prevent the deadlock forming:
`em`/`emt` start the *managed* unit (`systemctl --user start emacs`) rather
than spawning a competing `emacs --daemon`, the unit clears its own stale
socket on `ExecStartPre`, and `StartLimitBurst` bounds the restart loop so a
real failure surfaces as a stopped service instead of a silent CPU drain.

## Secrets Management

Uses [sops-nix](https://github.com/Mic92/sops-nix) with age encryption.

### Current secrets

- `github_token` - GitHub API token
- `dockerhub_token` - Docker Hub token
- `cachix_token` - Cachix auth token (for pushing to the binary cache)
- `flake_update_token` - GitHub fine-grained PAT so weekly flake-update PRs trigger CI and auto-merge (see [.github/SETUP.md](.github/SETUP.md))
- `porkbun/api_key` - Porkbun DNS API key
- `porkbun/secret_key` - Porkbun DNS API secret key
- `ssh/id_rsa` - SSH private key (synced to `~/.ssh/id_rsa`)
- `ssh/id_rsa_pub` - SSH public key
- `gpg/private_key` - GPG private key (for commit signing)
- `gpg/public_key` - GPG public key
- `org_gcal/client_id` - Google OAuth client id for org-gcal calendar sync
- `org_gcal/client_secret` - Google OAuth client secret for org-gcal
- `cloudflare/orrery_token` - Pages + DNS + Access on the fosterthecode.com zone (CI uses it)
- `cloudflare/tunnel_token` - Cloudflare Tunnel:Edit only — provisions the warealien tunnel
- `org_gcal/gpg_private_key` - **retired, and nothing reads it.** It was a passphrase-less GPG key encrypting Doom's org-gcal OAuth token store for a prompt-free decrypt. Activation no longer decrypts or imports it; the token store is a plain `0600` file (see [Emacs](#emacs)). Removing it from this file needs `sops unset` and deleting it from each keyring is manual — see [`modules/emacs/RETIRING-DOOM.md`](modules/emacs/RETIRING-DOOM.md).

### Edit secrets

```bash
sops secrets/secrets.yaml
```

### Security

- **Safe to commit:** `secrets/secrets.yaml` (encrypted), `.sops.yaml` (public keys)
- **Never commit:** `~/.config/sops/age/keys.txt` (private key)

## GPG Commit Signing

Commits are automatically signed with GPG when `my.git.signing.enable = true` (default).

The signing key is configured in `config.nix`:

```nix
git = {
  userName = "Your Name";
  userEmail = "your@email.com";
  signingKey = "YOUR_GPG_KEY_ID";  # Used by modules/git.nix
};
```

### Setup GPG key for GitHub

After `hms`, your GPG key is imported. To add it to GitHub:

```bash
# Copy public key to clipboard
gpg --armor --export YOUR_KEY_ID | pbcopy  # macOS
gpg --armor --export YOUR_KEY_ID | xclip   # Linux

# Find your key ID
gpg --list-secret-keys --keyid-format=long
```

Then: **GitHub → Settings → SSH and GPG keys → New GPG key** → paste.

### Verify signing works

```bash
# Check git config
git config --list | grep -E '(sign|gpg)'

# Test signing
echo "test" | gpg --clearsign

# View signature on commits
git log --show-signature -1
```

### WSL + YubiKey (forwardToWindows)

If you use a YubiKey for signing in WSL and don't want to use `usbipd` to pass the USB device through, enable the Windows Gpg4win bridge:

```nix
my.gpg = {
  enable = true;
  forwardToWindows = true;
};
```

**Requirements:**
- [Gpg4win](https://www.gpg4win.org/) installed on Windows with your key imported
- YubiKey inserted in a Windows USB port (not passed through to WSL)

**How it works:** A Python bridge (`gpg-win-bridge`) runs as a systemd user service. It owns the WSL `gpg-agent` socket and proxies Assuan protocol traffic to the Windows Gpg4win agent over TCP. Card detection uses `SCD SERIALNO` — when the YubiKey is absent the bridge falls back to a local software key (prompts for passphrase in the terminal or Emacs minibuffer).

**Signing flow:**
- Card present → Windows PIN dialog + YubiKey touch → signed
- Card absent → passphrase prompt (loopback pinentry) → signed

```bash
# Reset the bridge after reinserting the YubiKey
gpg-restart

# Watch bridge logs
journalctl --user -u gpg-win-bridge -f
```

### Troubleshooting GPG

If signing fails:

```bash
# Restart gpg-agent (standard setup)
gpgconf --kill all

# Reset the Windows bridge (forwardToWindows setup)
gpg-restart

# Set TTY (should be automatic after hms)
export GPG_TTY=$(tty)
```

## Flake Updates

```bash
# Update all inputs (weekly/monthly)
nfu
nix flake check
hms
git add flake.lock
git commit -m "chore: update flake inputs"
git push

# Update single input
nix flake update <n>
```

## CI Pipeline

```
ci.yml (push + PRs):
lint (statix, deadnix, alejandra --check, shellcheck, actionlint — all from
  │   .#lint-tools, this flake's own pinned nixpkgs, never the runner registry)
  ├─> check (ubuntu: nix flake check --all-systems + dry-run eval of Linux)
  └─> eval-darwin (ubuntu-latest: dry-run eval of all 3 Darwin home configs,
      │            named explicitly from config.nix)
      └─[+check]─> build-home (ALWAYS runs; the MATRIX is what varies —
                     │         PRs build x86_64-linux only, pushes add
                     │         2× aarch64-darwin. Pushes to Cachix.
                     │         Also runs the Emacs gate, verify.sh)
                     └─> docker-build (build → load → smoke test → push if DOCKERHUB_TOKEN)
                           └─> docker-test (registry pull verification of the pushed image)

validate.yml (manual, weekly, or on hosts/**, flake.nix, flake.lock changes):
nixos (NixOS system build)    darwin (aarch64-darwin home config build)
```

Note: `nix flake check --all-systems` **is** used. It was not while the Doom Emacs setup was in the flake — that used import-from-derivation with `allowSubstitutes = false`, so evaluating a Darwin config required *building* Darwin derivations. It was restored after verifying it exits 0, not on the assumption that it would. It covers the Darwin home configurations indirectly but really: `flake check` does not know about `homeConfigurations`, but `perUserPackages` mirrors each into `packages.<system>.home-<username>` and those are walked. `eval-darwin` is kept, but not for the reason it was created. It was on `macos-14` because the Doom IFD meant evaluating a Darwin config required *building* Darwin derivations; with Doom gone, a Linux runner resolves the full `--dry-run` build plan against the substituters (verified: exit 0, a 1021-line plan). It stays because `--all-systems` covers Darwin only **incidentally** — through the `perUserPackages` mirroring — so gating or renaming that mirroring would make Darwin coverage vanish silently and all green, whereas `eval-darwin` names the three configs outright.

`build-home` deliberately has **no job-level `if`**. It used to, and it
therefore reported "skipping" on every pull request — so nothing in CI built the
Linux closure before merge, and a local `nix build` was the only thing between a
broken home configuration and master (observed on PR #14). A `jobs.<id>.if`
cannot see the matrix context, so it can only skip the whole job; the
event-dependence lives in the matrix instead. The `ci-emacs-gate` check below
guards exactly that.

The CI is fork-friendly - lint and check always run, push operations only run if secrets are configured.

### Regression guards

`nix flake check` builds these. Each one encodes a bug that already happened, so
none of them is a style preference — if one fails, read what it caught rather
than relaxing it. The nine guards below are defined on `x86_64-linux` only,
because the content they guard is identical across systems; the two
tmux-helper builds run on every system.

They live in `checks/`, one file per concern, so that two branches touching two
different guards do not conflict by construction — which is what a single
attrset in `flake.nix` guaranteed. `checks/default.nix` merges them and
documents the whole interface a guard file is handed.

| Check | What it refuses to let back in |
|---|---|
| `claude-settings-guards` | Claude Code attributing itself in commits/PRs (`attribution` must be `{commit: "", pr: ""}`), and `mcp__emacs__emacs_eval` being auto-allowed — arbitrary elisp is arbitrary shell |
| `docker-terminal-no-ssh-mount` | `~/.ssh` being bind-mounted into a container. It holds the sops-decrypted private key; SSH into containers is agent-forwarding only |
| `ci-emacs-gate` | (a) `build-home` regaining a job-level `if`, (b) no step running `modules/emacs/vanilla/verify.sh`, (c) anything in `ci.yml` running `emacs --batch` — batch does not load `init.el`, so a batch check reports success having loaded nothing |
| `lint-tools-pinned` | A linter resolved through `nixpkgs#` (that is the *runner's* registry, not this flake) in either the CI lint job or `verify.sh`, and `--impure` reappearing in `verify.sh` |
| `devshell-stays-light` | The git-hooks.nix installer or the linters getting back onto the `cd` path. That was ~56s of evaluation on every `cd` into the repo after a lock bump — and the lock bumps weekly, unattended |
| `install-hooks-installs-hooks` | The counterweight to the above: `nix run .#install-hooks` must really run the upstream installer and must not stamp success it did not achieve |
| `background-jobs-close-fds` | A background job in the dev-shell hooks that does not close inherited descriptors. direnv hands `.envrc` a pipe on FD 3 and reads it to EOF, so a child holding FD 3 blocks the caller — measured at 9364ms versus 713ms. `nohup`, `setsid` and double-forking all made no difference |
| `devshell-hook-lint` | A shell syntax error in `lib/dev-shell-hook.sh`, `lib/install-hooks.sh` or `lib/warm-direnv.sh`. `mkShell` never lints the `shellHook`, and it runs at an interactive prompt where a syntax error looks like a broken terminal |
| `branch-policy-hook` | The specflow branch-policy hook losing worktree-awareness, or ceasing to fail closed. It shipped blocking every worktree commit as if it were on master; the first fix then turned every parse miss into a silent ALLOW. Runs the shipped hook against a 43-case matrix, in both directions |

Plus `tmux-helper-build` and `tmux-helper-vet`, which are ordinary builds rather
than guards.

See [.github/SETUP.md](.github/SETUP.md) for detailed CI setup instructions.

## Module options

Every module gates on one `my.<name>.enable`. Three places switch them on, and
which one matters: `home/common.nix` (shared, overridable per host), a
`home/hosts/*.nix` layer (machine-specific), or the inline module in
`flake.nix` (every config, not host-overridable). This is the whole set — if a
module is not listed here, it does not exist:

| Option | Module | Where it is enabled |
|---|---|---|
| `my.zsh.enable` | `zsh.nix` | common |
| `my.git.enable`, `my.git.signing.enable` | `git.nix` | common |
| `my.gpg.enable` | `gpg.nix` | common (+ darwin overrides) |
| `my.btop.enable` | `btop.nix` | common |
| `my.devTools.enable` | `dev-tools.nix` | common — **not a safe thing to turn off**, see the table at the top |
| `my.sops.enable` | `sops.nix` | common |
| `my.dockerTerminal.enable` | `docker-terminal.nix` | common |
| `my.emacs.enable` | `emacs/default.nix` | `flake.nix` — every config, with `package` set to the vanilla build |
| `my.emacsDoctor.enable` | `emacs-doctor/default.nix` | `flake.nix` — every config (module itself is Linux-gated) |
| `my.emacsMcp.enable` | `emacs-mcp.nix` | common |
| `my.claudeCode.enable` | `claude-code.nix` | common |
| `my.claudeSkills.enable` | `claude-skills.nix` | common |
| `my.claudeSpecflow.enable` | `claude-specflow.nix` | common |
| `my.claudeKg.enable` | `claude-kg/default.nix` | WSL host |
| `my.searxng.enable` | `searxng/default.nix` | WSL host |
| `my.orreryMcp.enable` | `orrery-mcp.nix` | WSL host |
| `my.tmux.enable` | `tmux/default.nix` | `flake.nix` — every config (also sets `theme.preset = "nord"`) |
| `my.tmuxHelper.enable` | `tmux-helper/default.nix` | `flake.nix` — every config |
| `my.displayplacer.enable` | `displayplacer.nix` | darwin |
| `my.zscalerBypass.enable` | `zscaler-bypass.nix` | corporate Mac |

## Flake apps

Things you can `nix run` from this flake without switching your profile:

| App | What it does |
|---|---|
| `nix run '.'` | The default app: `emacs-vanilla` (below) |
| `nix run '.#docker-test'` | Build the terminal Docker image and test it locally (Linux only) |
| `nix run '.#install-hooks'` | Install the git pre-commit hooks, and materialise the pinned linters at `.direnv/lint-tools` (GC-rooted) so the dev-shell can put them on `PATH` without evaluating them on every `cd`. `--uninstall` removes them |
| `nix run '.#emacs-vanilla'` | Throwaway **foreground** Emacs — no daemon, no socket, no `hms`, so it cannot collide with the running daemon. Its `--init-directory` is a read-only store path on purpose: that run *is* the test that `early-init.el` redirects every writable path out of `user-emacs-directory`. |
| `nix run '.#tmux-experimental'` | tmux on the parallel `experimental` socket (`tmux -L experimental`) — the parallel-instance pattern this repo used to trial the config before it took the default slot. It has since graduated: `conf-experimental.nix` *is* the daily driver now, so this app is the same config on a second socket |
| `nix run '.#tmux-helper-install'` | Install `/usr/local/bin/tmux-helper` (macOS/BeyondTrust stable path) |

Buildable packages, not apps: `.#lint-tools` is the symlinkJoin of every
linter this repo gates on — `alejandra`, `statix`, `deadnix`, `shellcheck`,
`actionlint` — out of *this* flake's nixpkgs. `verify.sh` and the CI lint job
both resolve that derivation rather than `nix run nixpkgs#<tool>`, so local and
CI agree by construction instead of by coincidence; `lint-tools-pinned` guards
it. `.#home-<username>` is any declared user's activation package. Also
buildable: `.#tmux-helper` (the Go binary), `.#dockerImage` /
`.#dockerImageStream` / `.#dockerImageSlim` (the terminal images — the stream
variants pipe into `docker load` without materialising a tarball), and
`.#default`, which is the activation package for this host.

`packages.emacs-vanilla` and `packages.emacs-doctor` are exposed on Linux only,
so `nix flake check` does not try to build them on darwin.

## Docker

```bash
# Build and test locally
nix run '.#docker-test'

# Pull from Docker Hub (replace <dockerhub-user> from config.nix)
docker run -it --rm <dockerhub-user>/terminal:latest
```

## Caches

Uses [Cachix](https://cachix.org) for binary caching. Bootstrap configures this automatically based on `config.nix`.

For forks, either:
1. Create your own Cachix cache and update `repo.cachixCache` in `config.nix`
2. Remove the cachix lines from `~/.config/nix/nix.conf` to skip

## Adding a New Module

1. Create `modules/mymodule.nix`:
```nix
{ config, lib, pkgs, ... }:
let cfg = config.my.mymodule;
in {
  options.my.mymodule = {
    enable = lib.mkEnableOption "my module";
  };
  config = lib.mkIf cfg.enable {
    # configuration here
  };
}
```

2. Import in `flake.nix` modules list
3. Enable in `home/common.nix`: `my.mymodule.enable = true;`

## License

MIT
