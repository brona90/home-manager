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

Also update the config names in the `check` job's dry-run step and the `eval-darwin` job's config list to match your `config.nix`. All of them are evaluated on an ubuntu runner; x86_64-darwin is build-less everywhere in CI, because GitHub has no hosted Intel macOS runners.

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
lint (statix, deadnix, alejandra --check, shellcheck, actionlint
  │    — all from `.#lint-tools`, this flake's nixpkgs, never the registry)
  ├─> check (ubuntu: nix flake check + dry-run eval of the Linux config)
  └─> eval-darwin (ubuntu: dry-run eval of all 3 Darwin configs — no Mac needed since Doom went)
      └─[+check]─> build-home (PRs: x86_64-linux · pushes: + 2× aarch64-darwin; Cachix; runs the Emacs gate)
                     └─> docker-build (build → load → smoke test → push if DOCKERHUB_TOKEN)
                           └─> docker-test (registry pull verification)
```

`nix flake check --all-systems` **is** used. It was not, for as long as the Doom Emacs setup (nix-doom-emacs-unstraightened) was in the flake: that relies on import-from-derivation whose intermediate derivations set `allowSubstitutes = false`, so evaluating a Darwin config required *building* Darwin derivations, which a Linux runner cannot do. Doom is retired and the flag was restored after verifying it exits 0, rather than on the assumption that it would.

Darwin home configurations are covered by it, which is worth spelling out because it is indirect: `nix flake check` walks apps, devShells, packages and checks and does not know about `homeConfigurations`, but `perUserPackages` mirrors every one of them into `packages.<system>.home-<username>`. A local `--all-systems` run on x86_64-linux evaluated `packages.x86_64-darwin.home-gfoster`, `packages.aarch64-darwin.home-gfoster` and `packages.aarch64-darwin.home-888973`.

The `eval-darwin` job is kept anyway, but it **no longer runs on macOS**. The Mac was only ever needed for the Doom IFD described above; with that gone, a Linux runner evaluates and dry-runs the Darwin configs perfectly well (verified before the runner was changed: `nix build --dry-run` of `gfoster@aarch64-darwin` exits 0 on x86_64-linux and resolves the full build plan, and deliberately breaking a `home/darwin.nix` assertion makes `nix flake check --all-systems` exit non-zero on Linux). The Rosetta `extra-platforms` line went with it — it only ever affected *building*, and this job does not build.

The job survives the overlap because the `check` job's Darwin coverage is **incidental**: it depends on `perUserPackages` mirroring the home configurations into `packages.<system>.home-<username>`. `eval-darwin` names the three configs outright, so the coverage is asserted rather than inherited. It is also a **required status check** on master, under the name `Evaluate Darwin Configurations` — removing or renaming the job means editing branch protection first, or every PR blocks forever on a check that never reports.

| Job | Trigger | What it does |
|-----|---------|--------------|
| `lint` | All pushes/PRs | statix, deadnix, alejandra formatting check, shellcheck, actionlint — each run from `nix build .#lint-tools`, **not** `nix run nixpkgs#<tool>`. See "Linters are pinned" below |
| `check` | After lint | `nix flake check --all-systems` + `nix build --dry-run` eval of the Linux config |
| `eval-darwin` | After lint (pushes/PRs) | `nix build --dry-run` eval of all Darwin configs in `config.nix`, on **ubuntu** — no Mac and no Rosetta since the Doom IFD was retired. Required status check: `Evaluate Darwin Configurations` |
| `build-home` | **PRs and pushes** | On a PR: builds `gfoster@x86_64-linux` only, then runs the Emacs gate (`modules/emacs/vanilla/verify.sh`). On a push to master: also both aarch64-darwin. Gated by the **matrix**, not a job-level `if` — the `if` is what made it skip on every PR. x86_64-darwin is eval-only (no hosted Intel macOS runners). The Cachix push is filtered: only paths *not* already signed by cache.nixos.org are uploaded (no point mirroring thousands of upstream paths), and it runs *before* the Emacs gate so a red gate still leaves the closure cached |
| `docker-build` | After build-home | Builds Docker image, loads it, smoke-tests it locally, and only then pushes to Docker Hub if token set |
| `docker-test` | After docker-build | Pulls the pushed image from Docker Hub and verifies it runs; reports "skipped — no token" in the job summary if `DOCKERHUB_TOKEN` is unset |

NixOS and Darwin full system builds are in `.github/workflows/validate.yml` (manual, weekly, or on `hosts/**`/`flake.lock`/`flake.nix` changes).

### Linters are pinned to this flake

Every linter in the `lint` job comes from `packages.<system>.lint-tools`
(`lib/lint-tools.nix`), built once into `/tmp/lint-tools` and invoked by
absolute path.

These steps used to be `nix run nixpkgs#<tool>`, which resolves through the
**runner's** flake registry — a property of the machine, not of the repo. CI and
a developer's laptop therefore ran different versions of the same tool, and the
failure mode is invisible until the day the versions disagree: PR #21 went red
because shellcheck renumbered a finding (`SC2329` in 0.11, `SC2317` before it),
`modules/emacs/vanilla/verify.sh` suppressed only the newer code, and the
registry served an older shellcheck than the local profile had.

`modules/emacs/vanilla/verify.sh` resolves the same derivation, so the two agree
by construction, and the `lint-tools-pinned` flake check fails the build if
either one reaches for `nixpkgs#` again.

The cost is that the `lint` job now evaluates the flake — fetching every input
rather than just the registry's nixpkgs. That is paid once per job, and the
`check` job pays it anyway. Do not "optimise" it back.

The job's last step prints the dereferenced store path of each linter. That is
the artefact to compare against a local run the next time anyone suspects
version skew (`statix` has no `--version` flag, so paths rather than versions).

### Retrying transient fetch failures

`.github/actions/nix-build-retry` is a composite action that builds (or dry-runs)
a set of flake targets and retries the **whole set** on failure — three attempts,
60 s apart by default.

It was written for nix-doom-emacs-unstraightened, which resolved elisp sources
through import-from-derivation with `allowSubstitutes = false` on the
intermediate derivations — plain git fetches of non-GitHub hosts (codeberg,
gitlab, savannah) that no binary cache could serve. **nix-doom is gone** (zero
matches in `flake.lock`), and with it that specific failure mode; the retry is
kept for the general one, because nix's own `download-attempts` covers
*substituter* downloads only, so any transient 408 or 504 on a fetched input
still fails an otherwise-green job.

Retrying is cheap: whatever a failed attempt did fetch is already in the store,
so a retry resumes rather than restarts. Note the `nix-args` input is
deliberately word-split, so it must not contain arguments with spaces.

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

Protection requires exactly the checks that run in PR context. The docker jobs remain push-gated and must *not* be listed, or auto-merge would wait forever.

**`build-home` now reports on PRs and belongs in this list.** It used to be push-gated by a job-level `if`, which meant nothing in CI built the Linux home configuration on a pull request — verified on PR #14, where it showed `skipping` while everything else passed. The event-dependence now lives in the matrix instead: PRs build `gfoster@x86_64-linux` only, pushes still build all three. The context name is the **matrix** name, parameters included:

```
Build Home Configurations (gfoster@x86_64-linux, ubuntu-latest)
```

Requiring it also requires the Emacs gate, which runs as a step inside that job. `nix flake check` cannot cover that gate: it has to start a real daemon, because `emacs --batch` does not load `init.el` at all and would report success while loading nothing.

```bash
gh api -X PUT repos/<owner>/<repo>/branches/master/protection --input - <<'EOF'
{
  "required_status_checks": {
    "strict": false,
    "contexts": [
      "Lint",
      "Flake Check",
      "Evaluate Darwin Configurations",
      "Build Home Configurations (gfoster@x86_64-linux, ubuntu-latest)"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

Check what is actually required rather than assuming the call took:

```bash
gh api repos/<owner>/<repo>/branches/master/protection --jq '.required_status_checks.contexts'
```

**Until `build-home` is in that list, `update-flake.yml` auto-merge can squash a lock bump once Lint / Flake Check / Evaluate Darwin pass — before the Linux build or the Emacs gate has reported.** That is the reason the gate exists, so it is not optional bookkeeping.

The matrix name is derived from `config.nix`; renaming the user, system or runner changes the context string, and a required check whose name no longer exists never reports, which blocks every PR forever. Update this list in the same commit as any such rename.

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
