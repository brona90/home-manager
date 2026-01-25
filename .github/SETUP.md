# GitHub Setup

## Required Secrets

For Docker Hub push to work, add these to your repo:

**Settings → Secrets and variables → Actions**

| Type | Name | Value |
|------|------|-------|
| Variable | `DOCKERHUB_USERNAME` | `brona90` |
| Secret | `DOCKERHUB_TOKEN` | Your Docker Hub access token |

### Creating a Docker Hub Token

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name: `github-actions`
4. Permissions: Read, Write, Delete
5. Copy the token

## CI Pipeline

The CI workflow (`.github/workflows/ci.yml`) runs:

| Job | Trigger | What it does |
|-----|---------|--------------|
| `check` | All pushes/PRs | Validates flake structure |
| `build` | After check | Builds home-manager and NixOS configs |
| `docker` | Merge to master | Builds, tests, pushes Docker image |

## Flake Updates

The update workflow (`.github/workflows/update-flake.yml`) runs weekly and creates PRs to update `flake.lock`.

## Using the Docker Image

```bash
# Latest
docker run -it --rm brona90/terminal:latest

# Specific date
docker run -it --rm brona90/terminal:20260124

# With SSH keys
docker run -it --rm -v ~/.ssh:/home/gfoster/.ssh:ro brona90/terminal:latest
```
