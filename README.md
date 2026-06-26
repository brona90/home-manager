# Home Manager Configuration

A reproducible, cross-platform development environment using [Nix](https://nixos.org/) flakes.

## What's Included

| Tool | Description |
|------|-------------|
| [Doom Emacs](https://github.com/doomemacs/doomemacs) | Emacs distribution with sensible defaults via [nix-doom-emacs-unstraightened](https://github.com/marienz/nix-doom-emacs-unstraightened) |
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
| `em`    | Emacs (GUI, uses daemon) |
| `emt`   | Emacs terminal |
| `emacs-doctor` | Inspect/reset/monitor the Emacs daemon + WSL health (`status`, `reset`, `gui-probe`, `watch`) — Linux only |
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
│   ├── emacs/             # Doom Emacs
│   ├── vim/               # LazyVim
│   ├── tmux/              # helper-driven tmux conf + 10 theme palettes
│   └── tmux-helper/       # Go helper binary (status, clipboard, theme, navigate, ...)
├── secrets/               # Encrypted secrets (safe to commit)
│   └── secrets.yaml
├── lib/                   # Helper functions
│   ├── docker-image.nix   # Docker image builder
│   └── docker-test-app.nix
└── .github/workflows/     # CI/CD
    ├── ci.yml             # Main pipeline
    ├── update-flake.yml   # Weekly flake.lock update PRs
    └── validate.yml       # NixOS/Darwin validation (manual, weekly, or on flake/hosts changes)
```

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

## Doom Emacs

This configuration uses [nix-doom-emacs-unstraightened](https://github.com/marienz/nix-doom-emacs-unstraightened) to provide a fully reproducible Doom Emacs setup. The Doom configuration files live in `modules/emacs/doom.d/`.

### Configuration Files

| File | Purpose |
|------|---------|
| `modules/emacs/doom.d/init.el` | Enable/disable Doom modules |
| `modules/emacs/doom.d/packages.el` | Declare additional packages |
| `modules/emacs/doom.d/config.el` | Personal configuration |

### Applying Changes

**Unlike standard Doom Emacs, you don't run `doom sync`.**

All changes to `doom.d/` files require a Home Manager rebuild:

```bash
# After editing doom.d files:
hms

# Restart emacs daemon to pick up changes:
systemctl --user restart emacs  # Linux with systemd
# Or manually:
emacsclient -e '(kill-emacs)'
em  # This will restart the daemon
```

### Adding Packages

Edit `modules/emacs/doom.d/packages.el`:

```elisp
;; Add a package from MELPA
(package! some-package)

;; Add a package from a git repo
(package! another-package
  :recipe (:host github :repo "user/repo"))

;; Pin a package to a specific commit
(package! pinned-package :pin "abc123")
```

Then rebuild: `hms`

### Enabling Doom Modules

Edit `modules/emacs/doom.d/init.el` and uncomment modules:

```elisp
:lang
(python +lsp +pyright)  ; enable python with LSP
(rust +lsp)             ; enable rust with LSP
```

Then rebuild: `hms`

### Why This Approach?

Traditional Doom Emacs uses `doom sync` which downloads packages imperatively. This creates reproducibility issues because packages can differ between machines.

With nix-doom-emacs-unstraightened:
- All packages are pinned in `flake.lock`
- Builds are reproducible across machines
- No network access needed after initial build
- Rollback is trivial (previous generations)

### Org Agenda & Google Calendar (org-gcal)

The org config wires up an agenda + capture workflow and two-way Google
Calendar sync. Agenda files (`inbox.org`, `todo.org`, `projects.org`, and the
`gcal*.org` calendars) live in `~/org/`; capture templates (`SPC X`) drop todos,
notes, and calendar events into the right file, and the TODO lifecycle is
`TODO → NEXT → WAIT → DONE/CANCELLED`.

[`org-gcal`](https://github.com/kidd/org-gcal.el) syncs those `gcal*.org` files
against Google Calendar. OAuth credentials are managed via sops (never in the
repo): `org_gcal/client_id` and `org_gcal/client_secret` are decrypted to
`~/.config/sops-nix/secrets/` on `hms`. The OAuth **token store** is encrypted
with a dedicated passphrase-less GPG key (`org_gcal/gpg_private_key`, imported
with full ownertrust on activation) so it decrypts with zero pinentry prompts.

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

### Troubleshooting Doom Emacs

```bash
# Check if emacs daemon is running
systemctl --user status emacs

# View daemon logs
journalctl --user -u emacs -f

# Force restart daemon
systemctl --user restart emacs

# Run emacs without daemon (for debugging)
emacs --debug-init

# Check what packages are installed
nix path-info -rsh $(which emacs) | sort -hk2 | tail -20
```

#### `emacs-doctor` — daemon health & recovery

The daemon is owned by the `emacs` systemd **user** unit. The failure mode to know
about: a stray standalone `emacs --daemon` can grab the server socket, the managed
`--fg-daemon` can then never bind it, and `Restart=on-failure` relaunches it forever —
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
clears stale sockets (`$XDG_RUNTIME_DIR/emacs/server`), `reset-failed`s, and starts a
single clean daemon.

Two safeguards in `modules/emacs/` prevent the deadlock from forming: the `em`/`emt`
wrappers start the *managed* unit (`systemctl --user start emacs`) instead of spawning a
competing `emacs --daemon`, and the unit itself clears a stale socket on `ExecStartPre`
and bounds its restart loop (`StartLimitBurst`) so a real failure surfaces as a stopped
service instead of a silent CPU drain.

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
- `org_gcal/gpg_private_key` - passphrase-less GPG key encrypting the org-gcal OAuth token store (prompt-free decrypt)

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
