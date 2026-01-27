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
    cachixCache = "your-cachix-cache";
  };
  # ...
}
```

### Step 2: Configure Repository Variables (Optional)

**Settings → Secrets and variables → Actions → Variables**

| Variable | Description | Example |
|----------|-------------|---------|
| `CACHIX_CACHE` | Your Cachix cache name | `myusername` |
| `DOCKER_USERNAME` | Your Docker Hub username | `myusername` |

### Step 3: Configure Secrets (Optional)

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
lint (statix, deadnix)
  └─> check (nix flake check)
        ├─> docker-build → docker-test (if DOCKERHUB_TOKEN set)
        └─> validate-nixos
```

| Job | Trigger | What it does |
|-----|---------|--------------|
| `lint` | All pushes/PRs | Static analysis with statix and deadnix |
| `check` | After lint | Validates flake structure |
| `docker-build` | Merge to main/master | Builds Docker image, pushes if credentials available |
| `docker-test` | After docker-build | Tests the pushed image |
| `validate-nixos` | After check | Builds NixOS configuration |

## Flake Updates

The update workflow (`.github/workflows/update-flake.yml`) runs weekly and creates PRs to update `flake.lock`.

## Using the Docker Image

```bash
# Latest (replace brona90 with your Docker Hub username)
docker run -it --rm brona90/terminal:latest

# Specific date
docker run -it --rm brona90/terminal:20260124

# With SSH keys
docker run -it --rm -v ~/.ssh:/home/gfoster/.ssh:ro brona90/terminal:latest
```
