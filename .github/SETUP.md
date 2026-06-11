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

Also update the config names in the `check` job's dry-run step and the `eval-darwin` job's config list to match your `config.nix` (x86_64-darwin configs are eval-only, via Rosetta on the arm64 macOS runner — GitHub has no hosted Intel macOS runners).

### Step 3: Configure Repository Variables (Optional)

**Settings → Secrets and variables → Actions → Variables**

| Variable | Description | Example |
|----------|-------------|---------|
| `CACHIX_CACHE` | Your Cachix cache name | `myusername` |
| `DOCKER_USERNAME` | Your Docker Hub username | `myusername` |

### Step 4: Configure Secrets (Optional)

**Settings → Secrets and variables → Actions → Secrets**

| Secret | Description | How to get it |
|--------|-------------|---------------|
| `CACHIX_AUTH_TOKEN` | Cachix auth token for pushing | [cachix.org](https://app.cachix.org) → Your cache → Settings → Auth Tokens |
| `DOCKERHUB_TOKEN` | Docker Hub access token | [hub.docker.com/settings/security](https://hub.docker.com/settings/security) → New Access Token |
| `FLAKE_UPDATE_TOKEN` | Fine-grained PAT so weekly flake-update PRs trigger CI | See [Flake Updates](#flake-updates) below |

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
lint (statix, deadnix, alejandra --check, shellcheck, actionlint)
  ├─> check (ubuntu: nix flake check + dry-run eval of the Linux config)
  └─> eval-darwin (macos-14: dry-run eval of all Darwin configs; x86_64-darwin via Rosetta)
      └─[+check]─> build-home (push only: x86_64-linux + 2× aarch64-darwin, pushes to Cachix)
                     └─> docker-build (build → load → smoke test → push if DOCKERHUB_TOKEN)
                           └─> docker-test (registry pull verification)
```

`nix flake check --all-systems` is intentionally not used: the Doom Emacs setup (nix-doom-emacs-unstraightened) relies on import-from-derivation whose intermediate derivations set `allowSubstitutes = false`, so evaluating a Darwin config requires *building* Darwin derivations — impossible on a Linux runner. The `eval-darwin` job provides that coverage on macOS instead, on PRs as well as pushes.

| Job | Trigger | What it does |
|-----|---------|--------------|
| `lint` | All pushes/PRs | statix, deadnix, alejandra formatting check, shellcheck, actionlint |
| `check` | After lint | `nix flake check` + `nix build --dry-run` eval of the Linux config |
| `eval-darwin` | After lint (pushes/PRs) | `nix build --dry-run` eval of all Darwin configs in `config.nix`; x86_64-darwin via Rosetta 2 (`extra-platforms`) |
| `build-home` | Merge to master | Builds home configs (x86_64-linux + both aarch64-darwin); pushes to Cachix if token set. x86_64-darwin is eval-only (no hosted Intel macOS runners). The Cachix push is filtered: only paths *not* already signed by cache.nixos.org are uploaded (no point mirroring thousands of upstream paths) |
| `docker-build` | After build-home | Builds Docker image, loads it, smoke-tests it locally, and only then pushes to Docker Hub if token set |
| `docker-test` | After docker-build | Pulls the pushed image from Docker Hub and verifies it runs; reports "skipped — no token" in the job summary if `DOCKERHUB_TOKEN` is unset |

NixOS and Darwin full system builds are in `.github/workflows/validate.yml` (manual, weekly, or on `hosts/**`/`flake.lock`/`flake.nix` changes).

## Flake Updates

The update workflow (`.github/workflows/update-flake.yml`) runs weekly: it updates `flake.lock`, validates it (`nix flake check` + a dry-run eval of the Linux config; Darwin eval needs a macOS runner and happens via the PR's CI), then opens a PR.

**Important — `GITHUB_TOKEN` trap:** PRs created with the default workflow token do **not** trigger `pull_request` workflows, so flake-update PRs would otherwise get no CI. To fix this, create a `FLAKE_UPDATE_TOKEN` secret:

1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token
2. Resource owner: you; Repository access: only this repo
3. Permissions: **Contents: Read and write**, **Pull requests: Read and write**
4. Add it as a repository secret named `FLAKE_UPDATE_TOKEN` (Settings → Secrets and variables → Actions → Secrets)
5. Also store it in sops (`sops secrets/secrets.yaml`, key `flake_update_token`) — GitHub secrets are write-only, so the sops copy is the recovery source

Without the PAT the workflow still works (the validation step gates the update), but the created PR will show no checks and will **not** be auto-merged.

### Auto-merge for flake-update PRs

After creating/updating the PR, the workflow runs `gh pr merge --auto --squash` with `FLAKE_UPDATE_TOKEN`, so the PR merges itself once its required checks pass — no human in the loop for routine lock bumps. The step is skipped gracefully when no PR was created this run or when `FLAKE_UPDATE_TOKEN` is unset (a `GITHUB_TOKEN`-created PR triggers no CI, so its required checks would never report anyway).

Auto-merge only waits for checks because of branch protection (below); two repo-side settings make it work:

1. Repo setting **Allow auto-merge** (`gh repo edit <owner>/<repo> --enable-auto-merge`)
2. Branch protection on `master` requiring the PR-context checks

### Branch protection on `master`

Protection requires exactly the three checks that run in PR context — `Lint`, `Flake Check`, `Evaluate Darwin Configurations` (`build-home` and the docker jobs are push-gated and must *not* be listed, or auto-merge would wait forever). Applied with:

```bash
gh api -X PUT repos/<owner>/<repo>/branches/master/protection --input - <<'EOF'
{
  "required_status_checks": {
    "strict": false,
    "contexts": ["Lint", "Flake Check", "Evaluate Darwin Configurations"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

**`enforce_admins: false` is load-bearing:** the repo owner routinely pushes directly to `master`, and with admin enforcement off, none of the protection rules apply to admins — direct pushes keep working exactly as before. The required checks only constrain PRs (i.e. the automated flake-update PRs) and non-admin pushes. Do not flip `enforce_admins` on without rethinking the direct-push workflow.

### nixpkgs unpin tracker

`flake.nix` temporarily pins nixpkgs to rev `8c3cede7` because nixos-unstable does not yet contain nixpkgs PR #529355 (merge commit `95e9e11e`), which fixes the darwin emacs 30.2 build. Tracking issue: [#1](https://github.com/brona90/home-manager/issues/1).

Each weekly run of `update-flake.yml` checks `gh api repos/NixOS/nixpkgs/compare/95e9e11e...nixos-unstable --jq .status`; when the channel contains the fix (`ahead`/`identical`), it comments once on the tracking issue that the pin can be removed. The step is best-effort (`continue-on-error`) and never fails the workflow.

**Disaster recovery:** all Actions secrets and variables can be replayed from
sops-decrypted files with one command (defined in `modules/sops.nix`):

```bash
repo-secrets-restore            # restores CACHIX_AUTH_TOKEN, DOCKERHUB_TOKEN,
                                # FLAKE_UPDATE_TOKEN, DOCKERHUB_USERNAME
repo-secrets-restore owner/repo # target a fork
```

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
