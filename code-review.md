# Deep Repo Review — 2026-06-10

> **Status: all findings addressed (same day).** Every high/medium/low item below was
> fixed in the working tree, with two deliberate deviations:
> 1. (H1) `nix flake check --all-systems` / ubuntu-side Darwin dry-runs are **impossible
>    in this repo**: nix-doom-emacs-unstraightened uses import-from-derivation with
>    `allowSubstitutes = false`, so merely evaluating a Darwin config requires building
>    Darwin derivations. Replaced with a PR-scoped `eval-darwin` job on `macos-14`
>    (x86_64-darwin evaluated via Rosetta `extra-platforms`).
> 2. (M17) `claude-diff-deny` no longer touches the working tree at all (the pending
>    edit isn't applied yet at PermissionRequest time, so `git checkout` could only
>    destroy *earlier* uncommitted work) — it now just dismisses the diff.
>
> Verified: alejandra/statix/deadnix/shellcheck/actionlint clean; `go vet` + `go test`
> pass (incl. new tests for the Darwin comm shape, shellquote, valued ssh flags);
> flake evaluates all 4 configs; dry-run build of gfoster@x86_64-linux succeeds;
> lvim verified empirically (7 → 333 treesitter parsers, Mason gone, grug-far present).

> **Addendum, 2026-08-24 — H1 was not fully closed on the day.** The status
> above records H1 as addressed via deviation 1, but that deviation covers only
> the *Darwin evaluation* half. H1's first bullet — "PRs never build configs",
> `build-home` gated to `push` — stayed open: PR #14 later observed the job
> reporting `skipping` on a pull request while every other check passed, and it
> was fixed in **#21**, which moved the event-dependence into the matrix and
> made `build-home` report on PRs. The "Overall assessment" sentence claiming
> PRs "merge without any build validation" was therefore accurate for longer
> than this header implies.
>
> Now closed, and guarded: `checks.ci-emacs-gate` fails the build if
> `build-home` regains a job-level `if`, if no step runs the Emacs gate, or if
> anything in `ci.yml` runs Emacs under `--batch`. The remaining H1 bullets —
> the flake-update PAT and validate.yml's silently no-opping Darwin job — were
> addressed as described. Findings below are left exactly as written; this note
> exists so nobody reads the header as "all clear" and stops checking.

Five parallel review passes: Nix core, security, Go tmux-helper, CI/docs, editor+Docker.
All findings verified against the actual code (go vet clean, all Go tests pass; Neovim
findings verified empirically with `lvim --headless`).

Severity: 🔴 high · 🟡 medium · ⚪ low

---

## 🔴 High

### H1. CI safety net has three compounding holes — the only real build gate is post-merge on master
- **PRs never build (or even evaluate Darwin) configs.** `ci.yml:68` gates `build-home` to `push`; PRs get only lint + `nix flake check`, and since Nix 2.13 `flake check` without `--all-systems` evaluates the current system only. A PR that breaks Darwin eval merges green.
  Fix: `nix flake check --all-systems` in the `check` job, and/or PR-time `nix build --dry-run` per config.
- **Weekly flake-update PRs trigger zero CI.** `update-flake.yml:23-28` uses the default `GITHUB_TOKEN`; PRs created with it don't fire `pull_request` workflows, and the workflow itself runs no check after updating. Fix: pass a PAT/App token via `token:`, and add a `nix flake check` step post-update.
- **validate.yml Darwin job has never validated anything.** `validate.yml:70` parses `nix flake show --json`, which emits `homeConfigurations: {"type":"unknown"}` (non-standard outputs aren't enumerated) → grep finds nothing → silent skip, masked by `2>/dev/null || echo ""`. Fix: `nix eval --json '.#homeConfigurations' --apply builtins.attrNames` (verified working), and stop swallowing eval errors.

### H2. The documented bootstrap one-liner cannot work
`README.md:35` says `curl -fsSL .../bootstrap.sh | bash`, but bootstrap.sh uses bare `read -r` for every prompt (lines 242, 246, 340, 349, 355-358, 450). When piped, stdin is the script stream — at EOF by the time `main` prompts, so `set -euo pipefail` aborts at "Enter username". Fix: `read -r ... </dev/tty` (or a `prompt_read` helper), or document `bash <(curl ...)`.

### H3. Always-allowed `emacs_eval` is an unguarded arbitrary-code-execution path for the agent
`modules/claude-code.nix:140-141` and `.claude/settings.local.json:7-8` permanently allow `mcp__emacs__emacs_eval` (plus `Bash(emacsclient:*)`). The MCP server passes `expression` straight to `emacsclient --eval` (`emacs-mcp-server.py:162-206`); arbitrary elisp = `(shell-command ...)` = arbitrary code as your user, bypassing every other permission guard *and* the entire diff-review hook flow. Any prompt-injected content (WebFetch page, malicious file under review) can use it silently. Fix: drop `emacs_eval` from always-allow (keep `emacs_show_diff`), or replace eval with narrow named MCP tools.

### H4. tmux-helper SSH/LLM detection is silently broken on macOS
On Darwin `ps -o comm=` prints full paths, unlike Linux. `internal/system/paneinfo.go:56-65` compares against bare `"ssh"`/`"mosh-client"` → never matches on the Mac; `cmds/status.go:175-177` strips `.`/`-wrapped` *before* `filepath.Base`, so Nix-wrapped binaries (`/nix/store/.../.claude-wrapped`) come out as `.claude` and the 🤖 indicator misses exactly the case the comment claims to handle. Fix: `filepath.Base` first, then strip.

### H5. Shell injection via unquoted tmux format expansions into `sh -c`
`internal/theme/theme.go:130` embeds `#{pane_current_path}` in a `#()` status job; tmux expands the format *before* `sh -c`, so a directory named `; rm -rf ~;` (tarball, cloned repo) executes on every status refresh. Same class in `modules/tmux/conf-experimental.nix:106` (`#{session_name}`) and :131-132 (`fpp`/`urlview` with `#{pane_current_path}`). Even benignly, paths with spaces split argv. Fix: use tmux's quoting modifier `#{q:pane_current_path}` / `#{q:session_name}` in both places.

### H6. Neovim: both pillars of the "Nix-managed plugins" design are broken in practice
- **Treesitter grammars are wiped from the runtimepath.** `init.lua:6-8` appends `$TREESITTER_GRAMMARS` to rtp before `lazy.setup()`, but lazy.nvim's default `performance.rtp.reset = true` rebuilds rtp, discarding it. Verified: `lvim --headless` finds only the 7 `$VIMRUNTIME` bundled parsers — the entire `withAllGrammars` pre-fetch (`modules/vim/default.nix:37-40`) is dead at runtime. Fix: pass it via lazy's supported `performance.rtp.paths` (appended after the reset).
- **Mason is not disabled.** No Lua spec disables it; LazyVim v15 auto-installs tools at runtime. Verified on disk: `~/.local/share/nvim/mason/bin/` contains lua-language-server, stylua, shfmt — duplicating/shadowing the Nix-provided binaries. Fix: `lua/plugins/mason.lua` with `{ "mason-org/mason.nvim", enabled = false }, { "mason-org/mason-lspconfig.nvim", enabled = false }`; LazyVim falls back to PATH binaries.

---

## 🟡 Medium

### Nix core
- **M1. `userForSystem` picks the wrong default on aarch64-darwin** (`flake.nix:195-200`): `builtins.head` matches gfoster first, so on the corporate Mac (888973) `packages.default`/`apps.default` build/activate gfoster's config. Fix: have `apps.default` use `$USER@${system}` at runtime, or expose per-user package names.
- **M2. `home/linux.nix` is a de-facto gfoster/WSL host file applied to all Linux** (lines 20-51): hardcoded personal builder hostnames/keys, sops-dependent SSH key path, `my.gpg.forwardToWindows = true` — all inherited by any future Linux user/system. Fix: gate behind username or a `my.wsl.enable` option; move builder list into config.nix/config.local.nix.
- **M3. Homebrew activation block is network-dependent and aborts activation on failure** (`home/darwin.nix:34-71`): runs `brew install` for 15 packages on every `hms` under `set -eu`; offline or one flaky cask kills the rest of activation; fresh-machine install needs interactive sudo despite `NONINTERACTIVE=1`. Fix: check `brew list` first, never let brew's exit code propagate, consider moving bootstrap to a `nix run` app.
- **M4. `modules/emacs-mcp.nix:26` pulls vanilla `pkgs.emacs` into the closure** just for `emacsclient` — a second full Emacs (darwin build risk, version skew vs. the Doom daemon). Fix: use `config.my.emacs.package` in `makeBinPath`.
- **M5. `modules/pinentry-emacs-frame.nix` is dead code and not module-shaped** — referenced nowhere; it's a bare derivation that would fail eval if added to the modules list. Delete (with the .sh) or wrap as a proper `options.my.*` module.

### Security
- **M6. gpg-win-bridge stages a .ps1 in predictable world-shared Windows Temp and runs it with `-ExecutionPolicy Bypass`** (`gpg-win-bridge.py:15-28`): TOCTOU — anyone who can write that path gets code exec in your Windows user context on every signature popup. Fix: per-invocation path in a restricted-ACL dir, or inline `powershell -Command`.
- **M7. bootstrap.sh auto-adds you to nix `trusted-users` without surfacing the privilege implication** (lines 122-153). Fix: prompt/warn; trusted-users can influence root-built derivations.
- **M8. `terminal` bind-mounts all of `~/.ssh` (incl. the sops-decrypted private key) into containers, with `--network host`** (`docker-terminal.nix:67,96-98`). Agent forwarding is already wired up — drop the key mount.

### CI / docs
- **M9. Only 2 of 4 declared homeConfigurations are ever built** (`ci.yml:69-75`); `gfoster@x86_64-darwin` and `gfoster@aarch64-darwin` are never built or evaluated by any workflow.
- **M10. docker-build pushes `:latest` before docker-test runs** (`ci.yml:166-186`) — a broken image goes live before the smoke test. Test the locally-loaded image before push, or push dated tag → test → retag.
- **M11. No concurrency groups in any workflow** — rapid pushes stack 60-min macOS jobs and race two `:latest` pushes. Add `concurrency: { group: ..., cancel-in-progress: true }`.
- **M12. README drift**: `README.md:38` quick-start uses single quotes around `$HOME` (never expands); CI diagram at :577-582 describes jobs that don't exist (`validate-nixos`), omits build-home/alejandra/shellcheck — SETUP.md:91-96 has the correct one.

### Go tmux-helper
- **M13. SSH cache races and unstable key** (`internal/ssh/cache.go:70`, `cmds/status.go:82`): fixed `.tmp` path → concurrent status jobs corrupt each other (self-heals but defeats cache); `os.Getppid()` as cache key only works while `sh -c` exec-optimizes — pass `#{pid}` from the format instead. No cache pruning exists.
- **M14. `open-file` $EDITOR fallback can't work from copy-pipe** (`cmds/openfile.go:56-62`): no tty in that context; multi-word `$EDITOR` (exactly what this repo sets) breaks `exec.Command`; matched `~/` paths are passed verbatim (nothing expands `~`). Fix: expand `~`, host the editor in `tmux new-window`.
- **M15. ssh argv reconstruction loses quoting; fallback parser mis-skips valued flags** (`cmds/status.go:103`, `internal/ssh/detect.go:60-78`): `strings.Fields` flattens quoted args; `detectFromArgv` only knows `-p` takes a value, so `ssh -i key host` shows `key` as the host. Extend the valued-flag list; treat `ssh -G` failure as unknown.

### Emacs diff-review flow
- **M16. Diff auto-dismisses after 15 s while the decision is still pending** (`claude-diff.el:287-292`): PostToolUse only fires after approval, so the timer races the user's reading time. Lengthen to ~120 s or tie dismissal to resolution.
- **M17. `claude-diff-deny` resolves the git repo from whatever buffer is current and reverts pre-existing work** (`claude-diff.el:373`): wrong `default-directory` (often the vterm popup); and since the edit isn't applied yet at PermissionRequest time, `git checkout HEAD -- file` destroys *earlier* uncommitted changes, not Claude's. Bind `default-directory` to the target file's dir; reconsider touching the working tree at all on deny.
- **M18. `emacs_show_diff` elisp computes repo root from the daemon's arbitrary cwd** (`emacs-mcp-server.py:220-226`); outside a repo, stderr text becomes `default-directory` and garbage gets diffed as the "before" content. Set `default-directory` from the file path first; check `call-process` exit status.
- **M19. Docker uid mismatch makes `terminal` unusable on the Mac** (`docker-terminal.nix:73,88` vs `docker-image.nix:21`): tmpfs mounted with *host* uid (501 on macOS) while the image user is baked at 1000 → entrypoint `mkdir -p $HOME` fails under `set -e`. Hardcode 1000 in mount options or thread uid/gid from the flake.

---

## ⚪ Low

### Nix
- `modules/tmux/default.nix:36-48`: theme enum allows 10 of the 23 themes in themes.nix — derive it: `lib.types.enum (builtins.attrNames (import ./themes.nix))`.
- `modules/tmux-helper/default.nix:19-29`: `installSystemWide` defined, never read; `my.tmux.preferSystemPath` never set true anywhere, so the documented BeyondTrust path is unreachable. Delete / wire up.
- `modules/zsh.nix:107-115`: WSL aliases (`clip`, `explorer`, `cmd`, …) and `nrs` defined unconditionally on all platforms; `vim = "lvim"` breaks if `my.vim.enable = false`. Move to the WSL layer; guard with `lib.optionalAttrs config.my.vim.enable`.
- `home/linux.nix:31` + `home/darwin.nix:19`: `claude-code` package duplicated; natural owner is `modules/claude-code.nix`'s `mkIf` block.
- `modules/zsh.nix:123`: `zstyle ':omz:update' mode auto` is a no-op against read-only store oh-my-zsh; set `disabled`.
- `modules/claude-code.nix:176-179`: `~/.claude/settings.json` is a read-only store symlink — the CLI can't persist user-scope settings; intentional, but consider `mkOutOfStoreSymlink` if write-through ever matters.
- `modules/docker-terminal.nix:26-30`: `terminal -w` with no directory dies on `shift 2` under `set -e` with no message.

### Security hygiene
- `.claude/settings.local.json`: prune stale/odd entries — broad `Bash(grep:*)`/`ls`/`find`, a hardcoded one-shot tar extract (line 17), and a malformed gpg line (line 20).

### Go
- `internal/system/paneinfo.go:70-73`: `ProcessArgs` swallows its error → dead error branch + skipped negative-cache → full `ps -A` walk every refresh on failure.
- `cmds/urlview.go:26`, `cmds/fpp.go:18`: Go `%q` used as shell quoting (doesn't stop `$`/backticks); reuse picker.go's correct `quoteAll`.
- `cmds/picker.go`: `-t name` is prefix-matched (use `-t =name`); `new-session -s` rejects names with `.`/`:` — sanitize; tab/newline in paths breaks the line protocol.
- `internal/clipboard/backend.go`: `clip.exe` mojibake for non-ASCII (OEM codepage) — pipe via UTF-16LE or `powershell Set-Clipboard`.
- No timeouts on any exec (tmux, ps, ssh -G, git, pmset) — a hung `git rev-parse` freezes the status bar; add `exec.CommandContext` with 1-2 s.
- Battery "Not charging" semantics differ linux vs darwin; `package.nix:13` vendorHash comment misleading (null is correct/permanent); dead `style` identity func in theme.go:113.
- Test gaps: darwin full-path `comm` shape (would have caught H4), `quoteAll`, valued-flag ssh argv, gradient math; `cache_test.go` TestExpiry is TZ/New-Year's-flaky.

### Editor / MCP
- `emacs-mcp-server.py:130`: malformed JSON line kills the server — reply `-32700` and continue. `:269`: `(message "{escaped}")` breaks on `%` — use `(message "%s" ...)`. `:251`: `emacs_open_file` child inherits protocol stdout — add `capture_output=True`. No `ping` handler; `initialize` ignores client protocolVersion; stale "Content-Length framed" comment.
- Diff triggers twice per permission request (explicit hook eval + file-notify watcher on the same dir, `claude-code.nix:151` vs `claude-diff.el:396-421`); watcher can read partially-written input.json. Pick one mechanism; write temp + `mv`.
- `config.el:147-182`: claude-diff machinery only loads after first claude-code use (`use-package!` defers) — hook eval is a void-function error in a plain vterm. Load `claude-diff` eagerly.
- `claude-diff.el:163`: `Write` to a *new* file never shows a diff (file-exists-p guard) — exactly when review matters most.
- LazyVim: `grug-far.nvim` (core in v15, `<leader>sr`) not pre-fetched and `install.missing=false` → errors; `nvim-spectre` is a stale fetched-but-unused leftover. `modules/vim/default.nix:387-396`: plugin copies never refresh on store-path change until manual `vcc` — stamp the source path and re-copy on mismatch.
- `lib/docker-test-app.nix:17`: hardcodes `$HOME/.config/home-manager` flake path (breaks forks/other checkouts); `result` symlink lands in cwd.

### CI / docs
- README "Current secrets" omits `cachix_token` + porkbun keys; structure tree omits 6 existing modules and update-flake.yml; `nix flake lock --update-input` is deprecated (use `nix flake update <input>`); SETUP.md has no Step 3 and a stale "(manual trigger)" claim; docs should list "install Nix" + sudo as bootstrap prerequisites; unquoted `$GITHUB_OUTPUT` in validate.yml (consider actionlint in lint job); docker-test green-with-no-test when DOCKERHUB_TOKEN unset certifies nothing.
- dependabot.yml verified adequate as-is (gomod would be a no-op — tmux-helper has zero deps).

---

## Verified-clean areas

- **Secrets pipeline is the standout**: nothing plaintext in tree or full git history; no secret ever interpolated into the Nix store (paths only); 0400/0600 modes, umask 077, atomic tmp+mv with EXIT trap; porkbun keys read at runtime.
- **No TLS weakening anywhere**: zscaler-bypass is route-only (allowlisted /32 CIDRs via physical gateway) — no MITM, no CA, no verification disabled.
- **No network listeners**: MCP server is stdio-only; gpg-win-bridge binds a 0600 Unix socket; its TCP use is outbound with the standard libassuan nonce handshake.
- **CI token hygiene**: `permissions: contents: read`; cachix/dockerhub tokens only in push-gated jobs; no `${{ github.event.* }}` in run blocks; no pwn-request patterns.
- **Docker image** respects the no-fakeroot constraint (chmod a+rwX only), runs non-root, no baked credentials; entrypoint matches prior review fixes.
- **Doom/Nix wiring**: config flows through `hms` with no `doom sync` needed; elisp overlay/window-restore/scroll-sync logic is leak-free; MCP server fails closed (timeouts → proper isError) rather than hanging Claude Code.
- **Go code quality**: clean `go vet`, all tests pass, dependency-free, platform code properly build-tagged, exec/parse separation keeps parsers testable.

## Overall assessment

Architecture quality is well above average for a personal config: the `options.my.<tool>` convention is applied consistently, config.nix/config.local.nix is genuinely fork-friendly, the secrets pipeline is exemplary, and tricky decisions are documented in place. The problems cluster in three places: (1) the **CI safety net looks real but isn't** — PRs and flake-update PRs merge without any build validation, and the Darwin backstop has silently no-opped since inception; (2) **macOS is the under-tested platform** — tmux-helper's process detection, the Docker uid mismatch, and 2-of-4 configs never built all bite only on the Mac; (3) the **Neovim declarative story has drifted** — grammars and Mason both quietly do the opposite of the documented design. The single security item worth acting on today is removing `emacs_eval` from the always-allow list.
