# Home Manager Configuration

A reproducible, cross-platform development environment using [Nix](https://nixos.org/) flakes.

## What's Included

| Tool | Description |
|------|-------------|
| [Doom Emacs](https://github.com/doomemacs/doomemacs) | **Current daily driver.** Emacs distribution with sensible defaults via [nix-doom-emacs-unstraightened](https://github.com/marienz/nix-doom-emacs-unstraightened). Reached as `em` / `emt`. |
| [Vanilla Emacs](modules/emacs/vanilla) | Hand-built Emacs 30 config (no distribution) running as a **second daemon** on socket `vanilla`, Linux only — `emv` / `emvt`. On trial to replace Doom; `my.emacs.flavor` in `flake.nix` swaps which one is primary. See [GRADUATION.md](modules/emacs/vanilla/GRADUATION.md). |
| [LazyVim](https://www.lazyvim.org/) | Neovim setup with lazy.nvim plugin manager |
| [tmux + tmux-helper](modules/tmux-helper) | Helper-driven tmux config: 38 keybinds, 25 themes (`prefix T` to cycle), fzf popup pickers (`prefix s/w/./P`), SSH-aware status bar, smart-status indicators (git branch / nix-shell / active-LLM), copy-mode `o` opens selection in emacsclient. Replaces the 94 KB gpakosz config with a few hundred lines of native tmux + a one-shot Go binary (~2,100 LOC). |
| [Oh My Zsh](https://ohmyz.sh/) | Zsh framework with plugins: `git`, `z`, `zsh-fast-syntax-highlighting`, `zsh-history-substring-search` |
| [Starship](https://starship.rs/) | Fast, customizable shell prompt |
| [mise](https://mise.jdx.dev/) | Polyglot runtime manager. Used **per-project only** via `direnv use_mise` -- the global zsh integration is intentionally off (5+ s/prompt cost on WSL). Globally needed runtimes live in nixpkgs (`home.packages`). |
| [btop](https://github.com/aristocratos/btop) | Resource monitor with TUI |
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
| `nrs`   | NixOS rebuild switch (WSL host only — defined in `home/hosts/wsl.nix`) |
| `em`    | Emacs client (GUI frame, TTY when there is no display) for the **primary** flavour — Doom today, whichever `my.emacs.flavor` names. Starts the daemon if it is not answering. |
| `emt`   | Same, always a terminal frame |
| `emv` / `emvt` | The same pair for the **second** flavour, the vanilla daemon on socket `vanilla` (`emacsclient -s vanilla`) — Linux only. Named for the flavour, so after graduation Doom is `emd` / `emdt`. |
| `emacs-doctor` | Inspect/reset/monitor the **primary** Emacs daemon + WSL health (`status`, `reset`, `gui-probe`, `watch`) — Linux only |
| `lvim`  | LazyVim |
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

### Neovim (v = vim)

| Command | Description |
|---------|-------------|
| `vcc`   | Vim cache clean (removes all nvim data/cache) |

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
├── config.nix             # User & repo configuration (edit this!)
├── home/                  # Home Manager profiles
│   ├── common.nix         # Shared across all systems
│   ├── linux.nix          # Linux-specific (platform-generic)
│   ├── darwin.nix         # macOS-specific (platform-generic + shared brew-sync)
│   └── hosts/             # Machine-specific layers (mapped via users.*.hosts in config.nix)
│       ├── wsl.nix        # gfoster's WSL box: build farm, GPG bridge, /mnt/c aliases
│       ├── personal-mac.nix  # Personal MacBooks: Homebrew lists
│       └── corp-mac.nix   # Corporate Mac: Homebrew lists + Zscaler bypass
├── hosts/                 # NixOS configurations
│   ├── common/            # Shared NixOS settings
│   └── wsl/               # WSL-specific config
├── modules/               # Reusable Home Manager modules
│   ├── zsh.nix            # Shell config with oh-my-zsh
│   ├── git.nix            # Git + GPG signing
│   ├── gpg.nix            # GPG agent + YubiKey bridge (forwardToWindows)
│   ├── btop.nix           # System monitor
│   ├── sops.nix           # Secrets management
│   ├── claude-code.nix    # Claude Code CLI settings, hooks, MCP servers
│   ├── emacs-mcp.nix      # Emacs MCP server module
│   ├── emacs-mcp-server.py  # MCP stdio server bridging Claude Code → emacsclient
│   ├── docker-terminal.nix  # `terminal` wrapper for the Docker dev image
│   ├── displayplacer.nix  # macOS display layout (displayplacer)
│   ├── zscaler-bypass.nix # Route-only Zscaler bypass (allowlisted CIDRs)
│   ├── scripts/
│   │   └── gpg-win-bridge.py  # WSL→Gpg4win Assuan proxy
│   ├── emacs/             # Emacs — two flavours, one primary
│   │   ├── default.nix    # flavor switch, both daemons, both client wrappers
│   │   ├── doom.d/        # Doom config: init.el / packages.el / config.el
│   │   └── vanilla/       # Hand-built Emacs 30: package.nix (explicit package
│   │                      #   list) + config/{early-init,init}.el, config/lisp/*.el
│   ├── vim/               # LazyVim
│   ├── tmux/              # helper-driven tmux conf + 10 theme palettes
│   └── tmux-helper/       # Go helper binary (status, clipboard, theme, navigate, ...)
├── secrets/               # Encrypted secrets (safe to commit)
│   └── secrets.yaml
├── lib/                   # Helper functions
│   ├── docker-image.nix   # Docker image builder
│   ├── docker-test-app.nix
│   ├── dev-shell.nix      # devShell + hook bootstrap (see "Dev shell and git hooks")
│   ├── dev-shell-hook.sh  # the shellHook — runs on every `cd`, must stay cheap
│   ├── install-hooks.sh   # body of `nix run .#install-hooks`
│   ├── warm-direnv.sh     # post-merge/checkout/rewrite background cache warm
│   └── pre-commit-hooks.nix  # the hook set handed to git-hooks.nix
└── .github/workflows/     # CI/CD
    ├── ci.yml             # Main pipeline
    ├── update-flake.yml   # Weekly flake.lock update PRs
    └── validate.yml       # NixOS/Darwin validation (manual, weekly, or on flake/hosts changes)
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
`post-rewrite` hooks that refill the direnv cache in the background, so a
`git pull` that moves the lock does not leave the refill to ambush your next
`cd`. They never delay the git command and print nothing when they work.

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
- `x86_64-darwin` (Intel Mac)
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
vim .sops.yaml  # Add new public key
sops updatekeys secrets/secrets.yaml
git add -A && git commit -m "feat(sops): add <machine> key" && git push

# 4. On new machine:
cd ~/.config/home-manager
git pull
hms
```

## Emacs — two flavours

Two Emacs builds are configured and **exactly one of them is the daily driver**.
Doom, built reproducibly with
[nix-doom-emacs-unstraightened](https://github.com/marienz/nix-doom-emacs-unstraightened),
holds that slot today. A hand-built vanilla Emacs 30 config runs beside it as a
second daemon, on trial to take it over
(see [`modules/emacs/vanilla/GRADUATION.md`](modules/emacs/vanilla/GRADUATION.md)).

| | Doom | Vanilla |
|---|---|---|
| Today | **primary — the daily driver** | second daemon, Linux only |
| Built by | `pkgs.emacsWithDoom` (flake input) | `modules/emacs/vanilla/package.nix` (`pkgs.emacs` 30.2) |
| Config lives in | `modules/emacs/doom.d/` | `modules/emacs/vanilla/config/` → linked to `~/.config/emacs` |
| systemd user unit | `emacs` | `emacs-vanilla` |
| Server socket | `$XDG_RUNTIME_DIR/emacs/server` (**the default**) | `$XDG_RUNTIME_DIR/emacs/vanilla` |
| Reach it | `em`, `emt`, bare `emacsclient` | `emv`, `emvt`, `emacsclient -s vanilla` |
| Restarted by `hms`? | **No** (`X-RestartIfChanged = false`) | **Yes** (`X-RestartIfChanged = true`) |
| Try it without `hms` | — | `nix run .#emacs-vanilla` |

### Which socket is authoritative

`my.emacs.flavor` is an enum, `"doom"` or `"vanilla"`, and it is `"doom"` today.
**The primary flavour owns the default server socket**
(`$XDG_RUNTIME_DIR/emacs/server`); the other one always runs on a named socket.

Everything that has to find "the" Emacs without being told which follows the
primary automatically, because it reads the read-only `my.emacs.primaryPackage`
(which tracks `flavor`) rather than `my.emacs.package` (which is always Doom):
`em`/`emt`, `EDITOR`/`VISUAL`, `emacs-doctor`, and the `emacs` MCP server.

Only one Emacs package is ever on `PATH` — `home.path` is a `buildEnv` with
collisions fatal, so listing both would be a hard build failure on `bin/emacs`.
A bare `emacs` or `emacsclient` is therefore unambiguously the primary; the
secondary is reachable only through its wrappers and its unit, which name it by
absolute store path.

Graduation, and rollback, is one word in `flake.nix`:

```nix
my.emacs.flavor = "vanilla";   # vanilla takes the default socket
```

Doom does not disappear when that flips — it becomes the named-socket flavour,
`emacsclient -s doom`, reachable as `emd`/`emdt`. The wrappers are named after
the flavour, not after "experimental", precisely so this swap needs no renaming.

One module is a deliberate exception: `modules/orrery-mcp.nix` reads
`my.emacs.package` (Doom) on purpose. It only ever runs `emacs -Q --batch`,
where any Emacs works, so it reuses an Emacs already in the closure rather than
adding one. The consequence to know is that after graduation it keeps the Doom
closure alive for batch use — which is why retiring Doom is a separate step.

### Configuration Files

| File | Purpose |
|------|---------|
| `modules/emacs/doom.d/init.el` | **Doom** — enable/disable Doom modules |
| `modules/emacs/doom.d/packages.el` | **Doom** — declare additional packages |
| `modules/emacs/doom.d/config.el` | **Doom** — personal configuration |
| `modules/emacs/vanilla/package.nix` | **Vanilla** — the explicit package list, and the derivation that assembles the config |
| `modules/emacs/vanilla/config/early-init.el` | **Vanilla** — pre-UI setup; redirects every writable path (`eln-cache`, `custom.el`, auto-save, `recentf`, `transient`) out of `user-emacs-directory` |
| `modules/emacs/vanilla/config/init.el` | **Vanilla** — main configuration |
| `modules/emacs/vanilla/config/lisp/*.el` | **Vanilla** — `my-bindings.el` (the `SPC` leader), `my-org.el`, `my-secrets.el` |

`~/.config/emacs/` is an **output**, not a source: `xdg.configFile."emacs"` links
the vanilla tree there (`recursive = true`, so real directories are created and
Emacs can still write `custom.el`, `eln-cache/` and friends while every `.el`
stays store-managed). Editing files there is lost on the next `hms` — with one
escape hatch: `my.emacs.vanilla.manageConfig = false` stops linking and hands
the directory to a working copy, for iterating on `init.el` without an `hms`
per keystroke.

### Applying Changes

**You don't run `doom sync`** — and there is no vanilla equivalent either. Every
change to either tree requires a Home Manager rebuild:

```bash
# After editing doom.d/ or vanilla/:
hms

# The PRIMARY unit is deliberately NOT restarted by hms
# (X-RestartIfChanged = false, so a rebuild can never eat unsaved buffers):
systemctl --user restart emacs      # Linux with systemd
# Or manually:
emacsclient -e '(kill-emacs)'
em                                  # this restarts the daemon

# The vanilla unit needs nothing: X-RestartIfChanged = true, so hms has
# already restarted it and any open `emv` frames are gone. Just check it:
systemctl --user status emacs-vanilla
```

`systemctl --user restart emacs` restarts **only the primary daemon**. It does
not touch `emacs-vanilla` — and note that after `flavor` flips, "the `emacs`
unit" *is* the vanilla daemon and `emacs-vanilla` becomes `emacs-doom`.

### Adding Packages

**Doom** — edit `modules/emacs/doom.d/packages.el`:

```elisp
;; Add a package from MELPA
(package! some-package)

;; Add a package from a git repo
(package! another-package
  :recipe (:host github :repo "user/repo"))

;; Pin a package to a specific commit
(package! pinned-package :pin "abc123")
```

**Vanilla** — there is no `package!`. The package list is an **explicit,
hand-maintained list** in `modules/emacs/vanilla/package.nix`:

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

Then rebuild: `hms`

### Enabling Doom Modules

Edit `modules/emacs/doom.d/init.el` and uncomment modules:

```elisp
:lang
(python +lsp +pyright)  ; enable python with LSP
(rust +lsp)             ; enable rust with LSP
```

Then rebuild: `hms`

**Vanilla has no equivalent concept.** There is no module system and no flag
list to uncomment: a feature exists only if some file under `config/lisp/`
configures it *and* `package.nix` provides the package. Those two halves are
always edited together.

### Keybindings — the `SPC` leader

Both flavours are evil-mode with an `SPC` leader. Vanilla has its own
discoverable menu (`config/lisp/my-bindings.el`): 14 named prefixes and roughly
150 named leader keys, each showing a human-readable name in the which-key popup
— which-key is built into Emacs 30, so no package is involved.

The keys follow Doom's, with about ten **deliberate divergences** — keys where
Doom's command does not exist outside Doom, so the key is kept but the behaviour
differs (`SPC c e`, `SPC c d`, `SPC f D`, `SPC s l`, `SPC m r` and friends). The
divergence table lives in
[`modules/emacs/vanilla/GRADUATION.md`](modules/emacs/vanilla/GRADUATION.md)
("Deliberate differences from Doom — bindings") and is deliberately not copied
here, so the two cannot drift apart.

### Why This Approach?

Traditional Doom Emacs uses `doom sync` which downloads packages imperatively. This creates reproducibility issues because packages can differ between machines.

With nix-doom-emacs-unstraightened:
- All packages are pinned in `flake.lock`
- Builds are reproducible across machines
- No network access needed after initial build
- Rollback is trivial (previous generations)

The vanilla flavour reaches the same place by a different route: its packages
come from the Emacs package set of the nixpkgs pinned in `flake.lock`
(`baseEmacs.pkgs.withPackages`), named in one explicit list in `package.nix`, so
there is likewise nothing imperative to sync.

### Org Agenda & Google Calendar (org-gcal)

The org config wires up an agenda + capture workflow and two-way Google
Calendar sync. Agenda files (`inbox.org`, `todo.org`, `projects.org`, and the
`gcal*.org` calendars) live in `~/org/`; capture templates (`SPC X`) drop todos,
notes, and calendar events into the right file, and the TODO lifecycle is
`TODO → NEXT → WAIT → DONE/CANCELLED`. The vanilla flavour ports this same
setup (`config/lisp/my-org.el`); the two deliberate differences are the fetch
timer and the token store, both below.

[`org-gcal`](https://github.com/kidd/org-gcal.el) syncs those `gcal*.org` files
against Google Calendar. **Both flavours** do this, from the same sops-managed
OAuth credentials (never in the repo): `org_gcal/client_id` and
`org_gcal/client_secret` are decrypted to `~/.config/sops-nix/secrets/` on `hms`.

> **Cross-flavour data hazard.** Do **not** run a vanilla org-gcal fetch while
> Doom has a `gcal*.org` buffer open (or the reverse). Both write the same files
> in `~/org/`, and whichever has the buffer open hits "file changed on disk" —
> which turns a trial config into a data-loss question about real calendar
> entries. This is the one way the parallel instance can damage something the
> daily driver owns. For the same reason vanilla has **no** 30-minute background
> fetch timer (Doom keeps one); vanilla fetches by hand, `SPC m G f`.

The two keep **separate token stores, with deliberately different security
postures**:

| | Doom | Vanilla |
|---|---|---|
| Token store | `~/.config/org-gcal/oauth2-auto.plist` (plus `token.plstore`) | `~/.local/state/emacs/oauth2-auto.eld` |
| Protection | GPG-encrypted plstore, to a dedicated passphrase-less key (`org_gcal/gpg_private_key`, imported with full ownertrust on activation) so it decrypts with no pinentry prompt | a plain **`0600` file**, no encryption |

The vanilla choice is deliberate and argued at length in
`modules/emacs/vanilla/config/lisp/my-secrets.el`: Doom's store is encrypted to a
key whose *passphrase-less private half* sits at `0600` on the same disk, so the
encryption was never adding protection over the file mode. Encrypting to the
YubiKey key instead is not available while the fetch has to run unattended —
that trade-off is real and was made knowingly. Doom's arrangement is unchanged.

First-time setup (once):

1. Create a Google Cloud OAuth client (type "Desktop app") with the Calendar
   API enabled; add your Google account as a Test user.
2. Store the credentials in sops:
   ```bash
   sops set secrets/secrets.yaml '["org_gcal"]["client_id"]'     '"...id..."'
   sops set secrets/secrets.yaml '["org_gcal"]["client_secret"]' '"...secret..."'
   ```
3. `hms`, then in Emacs run `M-x org-gcal-sync` and complete the browser auth
   once. That authorises **Doom**.
4. To authorise **vanilla** without redoing the browser flow, run
   `M-x my/oauth2-import-from-plstore` once in `emv` and accept the default
   path. It reads Doom's plstore and writes the `.eld`; it does not move or
   modify Doom's store. That command is the only thing in the vanilla config
   that touches GPG, and it never runs on its own.

### Troubleshooting Emacs

There are **two** user units. `emacs` is the primary (Doom today); the second
flavour's unit is named after the flavour, `emacs-vanilla`.

```bash
# Check if the daemons are running
systemctl --user status emacs           # primary — owns %t/emacs/server
systemctl --user status emacs-vanilla   # second flavour — owns %t/emacs/vanilla

# View daemon logs
journalctl --user -u emacs -f
journalctl --user -u emacs-vanilla -f

# Force restart (each restarts only itself)
systemctl --user restart emacs
systemctl --user restart emacs-vanilla

# Which daemons are actually answering?
emacsclient -e '(emacs-version)'             # the primary
emacsclient -s vanilla -e '(emacs-version)'  # the vanilla daemon
ls -l "$XDG_RUNTIME_DIR/emacs/"              # both sockets live in one directory

# Run emacs without a daemon (for debugging)
emacs --debug-init                # the primary flavour
nix run .#emacs-vanilla           # throwaway foreground vanilla, no daemon,
                                  # no hms, no socket — cannot collide

# Check what packages are installed
nix path-info -rsh $(which emacs) | sort -hk2 | tail -20
```

#### `emacs-doctor` — daemon health & recovery

The primary daemon is owned by the `emacs` systemd **user** unit; the second
flavour has its own, `emacs-vanilla`. `emacs-doctor` diagnoses the **primary**
(it follows `my.emacs.primaryPackage` and the default socket) — for the other
flavour use plain `systemctl --user`/`journalctl --user -u emacs-vanilla`. The
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

**`$XDG_RUNTIME_DIR/emacs/` now holds two sockets** — `server` (primary) and
`vanilla` — so every clean-up here names **exactly one file**. Both units'
`ExecStartPre` is `rm -f %t/emacs/<one socket>`, never `rm -rf %t/emacs`: wiping
the directory would delete the other flavour's *live* socket and drop it into
precisely the crash loop described above.

The same safeguards in `modules/emacs/` prevent the deadlock forming, for both
flavours: each client wrapper starts its own *managed* unit
(`em`/`emt` → `systemctl --user start emacs`, `emv`/`emvt` →
`systemctl --user start emacs-vanilla`) instead of spawning a competing
`emacs --daemon`, and each unit clears its own stale socket on `ExecStartPre` and
bounds its restart loop (`StartLimitBurst`) so a real failure surfaces as a
stopped service instead of a silent CPU drain. The wrappers' raw fallback always
carries `--daemon=<server-name>`; a bare `emacs --daemon` from the vanilla
wrapper would squat the **primary's** socket and reproduce the deadlock against
the daily driver.

## LazyVim

This configuration provides a Nix-managed LazyVim setup where all plugins are pre-fetched and pinned. The wrapper script `lvim` handles the complexity of running LazyVim in a reproducible way.

### How It Works

The `modules/vim/default.nix` module:

1. **Pre-fetches plugins** - LazyVim and all plugins are fetched at Nix build time using `fetchFromGitHub`
2. **Uses nixpkgs treesitter grammars** - All grammars are pre-compiled, no runtime compilation
3. **Creates a wrapper script** (`lvim`) that:
   - Sets up environment variables (fonts, SSL, paths)
   - Copies pre-fetched plugins to `~/.local/share/nvim/lazy/`
   - Creates `.git` markers so lazy.nvim thinks plugins are installed
   - Runs neovim with the bundled config

### Configuration Files

| File | Purpose |
|------|---------|
| `modules/vim/nvim-config/init.lua` | Main entry point, loads LazyVim |
| `modules/vim/nvim-config/lua/config/options.lua` | Neovim options |
| `modules/vim/nvim-config/lua/plugins/theme.lua` | Theme configuration |
| `modules/vim/nvim-config/lua/plugins/treesitter.lua` | Treesitter overrides |

### Applying Changes

For config changes (lua files):
```bash
hms  # Rebuild home-manager
```

For plugin version updates, edit `modules/vim/default.nix`:
```nix
# Update lazy.nvim version
lazyNvim = pkgs.fetchFromGitHub {
  owner = "folke";
  repo = "lazy.nvim";
  rev = "v11.16.2";  # Change this
  sha256 = "...";     # nix will tell you the new hash
};

# Update LazyVim version
lazyVimDistro = pkgs.fetchFromGitHub {
  owner = "LazyVim";
  repo = "LazyVim";
  rev = "v15.13.0";  # Change this
  sha256 = "...";
};
```

Then rebuild and clear cache:
```bash
hms
vcc  # Clear nvim cache to force plugin reinstall
lvim
```

### Adding Plugins

Edit `modules/vim/default.nix` and add to the `pluginsDir` linkFarm:

```nix
pluginsDir = pkgs.linkFarm "lazy-plugins" [
  # ... existing plugins ...
  { name = "new-plugin.nvim"; path = vp.new-plugin-nvim; }  # from nixpkgs
  # Or fetch directly:
  { name = "custom-plugin"; path = pkgs.fetchFromGitHub {
      owner = "author";
      repo = "custom-plugin";
      rev = "v1.0.0";
      sha256 = "sha256-...";
    };
  }
];
```

Then create a lua config in `modules/vim/nvim-config/lua/plugins/`:

```lua
-- modules/vim/nvim-config/lua/plugins/new-plugin.lua
return {
  { "author/new-plugin.nvim", opts = {} }
}
```

Rebuild: `hms && vcc && lvim`

### Why This Approach?

Traditional LazyVim downloads plugins at runtime, which:
- Requires network access
- Can break if GitHub is slow/down
- Results in different versions across machines

With Nix-managed LazyVim:
- All plugins pinned in Nix
- No network access after build
- Reproducible across machines
- Treesitter grammars pre-compiled (faster startup)

### Limitations & Caveats

1. **Plugin updates require manual Nix changes** - You can't just run `:Lazy update`
2. **Mason is disabled** - LSP servers are managed by Nix, not Mason
3. **Some lazy.nvim features don't work** - Plugin installation, updates via UI
4. **Cache clearing sometimes needed** - After updates, run `vcc` to clear state

### Troubleshooting LazyVim

```bash
# Clear all nvim state (nuclear option)
vcc

# Check what's in the lazy plugins dir
ls -la ~/.local/share/nvim/lazy/

# Run with verbose output
lvim --startuptime /tmp/startup.log

# Check treesitter grammars
lvim -c ':TSInstallInfo'

# Debug LSP
lvim -c ':LspInfo'
```

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
- `org_gcal/gpg_private_key` - passphrase-less GPG key encrypting **Doom's** org-gcal OAuth token store, for a prompt-free decrypt. The vanilla flavour does not use it: its token store is a plain `0600` file (see [Emacs — two flavours](#emacs--two-flavours)). Retire this key only when Doom is retired.

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
lint (statix, deadnix, alejandra --check, shellcheck, actionlint)
  ├─> check (ubuntu: nix flake check + dry-run eval of the Linux config)
  └─> eval-darwin (macos-14: dry-run eval of all 3 Darwin configs;
      │            x86_64-darwin via Rosetta — no hosted Intel runners)
      └─[+check]─> build-home (push to master only: x86_64-linux + 2× aarch64-darwin, pushes to Cachix)
                     └─> docker-build (build → load → smoke test → push if DOCKERHUB_TOKEN)
                           └─> docker-test (registry pull verification of the pushed image)

validate.yml (manual, weekly, or on hosts/**, flake.nix, flake.lock changes):
nixos (NixOS system build)    darwin (aarch64-darwin home config build)
```

Note: `nix flake check --all-systems` is intentionally not used — the Doom Emacs setup uses import-from-derivation with `allowSubstitutes = false`, so Darwin configs can only be evaluated on a Darwin builder (hence the dedicated `eval-darwin` job).

The CI is fork-friendly - lint and check always run, push operations only run if secrets are configured.

See [.github/SETUP.md](.github/SETUP.md) for detailed CI setup instructions.

## Flake apps

Things you can `nix run` from this flake without switching your profile:

| App | What it does |
|---|---|
| `nix run '.#docker-test'` | Build the terminal Docker image and test it locally (Linux only) |
| `nix run '.#emacs-vanilla'` | Throwaway **foreground** vanilla Emacs — no daemon, no socket, no `hms`, so it cannot collide with either running daemon. Its `--init-directory` is a read-only store path on purpose: that run *is* the test that `early-init.el` redirects every writable path out of `user-emacs-directory`. |
| `nix run '.#tmux-experimental'` | tmux on the parallel `experimental` socket (`tmux -L experimental`), same precedent as the second Emacs flavour |
| `nix run '.#tmux-helper-install'` | Install `/usr/local/bin/tmux-helper` (macOS/BeyondTrust stable path) |
| `nix run '.#update-vim-plugins'` | Print refreshed lazy.nvim / LazyVim revisions and hashes for `modules/vim/default.nix` |

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
