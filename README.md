# Home Manager Configuration

A reproducible, cross-platform development environment using [Nix](https://nixos.org/) flakes.

## What's Included

| Tool | Description |
|------|-------------|
| [Doom Emacs](https://github.com/doomemacs/doomemacs) | Emacs distribution with sensible defaults via [nix-doom-emacs-unstraightened](https://github.com/marienz/nix-doom-emacs-unstraightened) |
| [LazyVim](https://www.lazyvim.org/) | Neovim setup with lazy.nvim plugin manager |
| [oh-my-tmux](https://github.com/gpakosz/.tmux) | tmux configuration with powerline-style status bar |
| [Oh My Zsh](https://ohmyz.sh/) | Zsh framework with plugins: `git`, `z`, `direnv`, `zsh-syntax-highlighting`, `zsh-history-substring-search` |
| [Starship](https://starship.rs/) | Fast, customizable shell prompt |
| [mise](https://mise.jdx.dev/) | Polyglot runtime manager (node, python, go, etc.) |
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
curl -fsSL https://raw.githubusercontent.com/brona90/home-manager/master/bootstrap.sh | bash

# Or if already have nix and repo cloned:
home-manager switch --flake '$HOME/.config/home-manager#USERNAME@SYSTEM' -b backup
```

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
       cachixCache = "your-cachix-cache";          # optional, or remove
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

4. **(Optional) Configure CI** - See [.github/SETUP.md](.github/SETUP.md)

## Commands

### General

| Command | Description |
|---------|-------------|
| `hms`   | Home Manager switch (rebuild config) |
| `nrs`   | NixOS rebuild switch |
| `em`    | Emacs (GUI, uses daemon) |
| `emt`   | Emacs terminal |
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
│   ├── linux.nix          # Linux-specific
│   └── darwin.nix         # macOS-specific
├── hosts/                 # NixOS configurations
│   ├── common/            # Shared NixOS settings
│   └── wsl/               # WSL-specific config
├── modules/               # Reusable Home Manager modules
│   ├── zsh.nix            # Shell config with oh-my-zsh
│   ├── git.nix            # Git + GPG signing
│   ├── btop.nix           # System monitor
│   ├── sops.nix           # Secrets management
│   ├── emacs/             # Doom Emacs
│   ├── vim/               # LazyVim
│   └── tmux/              # oh-my-tmux
├── secrets/               # Encrypted secrets (safe to commit)
│   └── secrets.yaml
├── lib/                   # Helper functions
│   ├── docker-image.nix   # Docker image builder
│   └── docker-test-app.nix
└── .github/workflows/     # CI/CD
    ├── ci.yml             # Main pipeline
    └── validate.yml       # Manual validation
```

## Supported Systems

- `x86_64-linux` (Debian, Ubuntu, NixOS, WSL)
- `aarch64-linux` (Raspberry Pi, ARM servers)
- `x86_64-darwin` (Intel Mac)
- `aarch64-darwin` (Apple Silicon Mac)

## New Machine Setup

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
- `ssh/id_rsa` - SSH private key (synced to `~/.ssh/id_rsa`)
- `ssh/id_rsa_pub` - SSH public key
- `gpg/private_key` - GPG private key (for commit signing)
- `gpg/public_key` - GPG public key

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

### Troubleshooting GPG

If signing fails:

```bash
# Restart gpg-agent
gpgconf --kill all

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
nix flake lock --update-input <n>
```

## CI Pipeline

```
lint (statix, deadnix)
  └─> check (nix flake check)
        ├─> docker-build → docker-test (if credentials available)
        └─> validate-nixos
```

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
