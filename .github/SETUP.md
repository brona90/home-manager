# GitHub Setup

## For Forkers

This repo is designed to be fork-friendly. The CI will work without any setup (lint and check will run), but to enable Docker push and Cachix push, configure the following:

### Step 1: Update `config.nix`

Edit the `repo` section with your values:

```nix
{
  repo = {
    owner = "your-github-username";
    name = "home-manager";
    dockerHubUser = "your-dockerhub-username";
    cachixCache = "your-cachix-cache";          # or remove if not using Cachix
    cachixPublicKey = "your-cache.cachix.org-1:base64pubkey=";  # optional; run `cachix use <cache>` to find it
  };
  # ...
}
```

### Step 2: Update `ci.yml` build matrix

The `build-home` job in `.github/workflows/ci.yml` has the original repo's usernames hardcoded. Update the matrix entries to match your `config.nix`:

```yaml
matrix:
  include:
    - config: youruser@x86_64-linux    # must match username@system in config.nix
      runner: ubuntu-latest
    - config: youruser@aarch64-darwin  # remove if you don't have a Darwin config
      runner: macos-14
```

### Step 4: Configure Repository Variables (Optional)

**Settings → Secrets and variables → Actions → Variables**

| Variable | Description | Example |
|----------|-------------|---------|
| `CACHIX_CACHE` | Your Cachix cache name | `myusername` |
| `DOCKER_USERNAME` | Your Docker Hub username | `myusername` |

### Step 5: Configure Secrets (Optional)

**Settings → Secrets and variables → Actions → Secrets**

| Secret | Description | How to get it |
|--------|-------------|---------------|
| `CACHIX_AUTH_TOKEN` | Cachix auth token for pushing | [cachix.org](https://app.cachix.org) → Your cache → Settings → Auth Tokens |
| `DOCKERHUB_TOKEN` | Docker Hub access token | [hub.docker.com/settings/security](https://hub.docker.com/settings/security) → New Access Token |

**Without these secrets:**
- ✅ Lint and flake check will still run
- ✅ Docker image will build (just not push)
- ✅ NixOS config will validate
- ❌ Docker image won't push to Docker Hub
- ❌ Builds won't push to Cachix

---

## For the Original Repo

### Required Secrets

| Secret | Value |
|--------|-------|
| `CACHIX_AUTH_TOKEN` | Cachix auth token |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

### Creating a Docker Hub Token

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name: `github-actions`
4. Permissions: Read, Write, Delete
5. Copy the token

### Creating a Cachix Auth Token

1. Go to https://app.cachix.org
2. Select your cache
3. Settings → Auth Tokens → Generate

---

## CI Pipeline

```
lint (statix, deadnix, alejandra --check, shellcheck)
  └─> check (nix flake check)
        ├─> build-home (push only: x86_64-linux + aarch64-darwin, pushes to Cachix)
        │     └─> docker-build → docker-test (requires DOCKERHUB_TOKEN)
        └─> validate-nixos (continue-on-error)
```

| Job | Trigger | What it does |
|-----|---------|--------------|
| `lint` | All pushes/PRs | statix, deadnix, alejandra formatting check, shellcheck |
| `check` | After lint | Validates flake structure with `nix flake check` |
| `build-home` | Merge to master | Builds home configs (x86_64-linux + aarch64-darwin); pushes to Cachix if token set |
| `docker-build` | After build-home | Builds Docker image; pushes to Docker Hub if token set |
| `docker-test` | After docker-build | Pulls and smoke-tests the pushed image |
| `validate-nixos` | After check | Builds NixOS configuration (continue-on-error) |

## Flake Updates

The update workflow (`.github/workflows/update-flake.yml`) runs weekly and creates PRs to update `flake.lock`.

## Using the Docker Image

Replace `<docker-user>` and `<username>` with values from your `config.nix`:

```bash
# Latest
docker run -it --rm <docker-user>/terminal:latest

# Specific date
docker run -it --rm <docker-user>/terminal:20260124

# With SSH keys
docker run -it --rm -v ~/.ssh:/home/<username>/.ssh:ro <docker-user>/terminal:latest
```
