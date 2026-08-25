# tmux Helper-Driven Config — Graduation Status

> **Status: GRADUATED.** The "dual stack" no longer exists. Phase 9
> (`bef7cf9`, 2026-04-29) cut the daily driver over to the helper-driven
> config; Phase 9.5 (`2953a51`, same day) removed the `useHelper`
> kill-switch. The gpakosz/.tmux config is gone from the tree — rollback is
> `git revert bef7cf9`. This doc records the final state, the open items
> that survived graduation, and the trial workflow (still useful for
> testing future config changes on a parallel socket).

This doc is also the **template** for the pattern: a parallel instance on its
own socket, kept until it earns the default slot. The hand-built Emacs config
followed it — `emacsclient -s vanilla` in place of `tmux -L experimental` — and
has since graduated and replaced Doom;
[`modules/emacs/vanilla/DESIGN.md`](../emacs/vanilla/DESIGN.md) is what its
trial document turned into once the trial was over, which is the other half of
the pattern.

## 1. Current state

| File | Role |
|---|---|
| `modules/tmux/default.nix` | The only tmux module. `options.my.tmux.{enable, theme.preset, preferSystemPath}`. Sources the generated conf; exports `TMUX_HELPER_CONF` / `TMUX_HELPER_THEMES` session vars. |
| `modules/tmux/conf-experimental.nix` | Pure function returning the conf text. Despite the name, this **is** the daily-driver config (imported by `default.nix` and by `apps.tmux-experimental`). |
| `modules/tmux/themes.nix` | 25 palettes (gpakosz, molokai, nord, catppuccin x4, tokyonight x3, rose-pine x3, gruvbox x2, solarized x2, everforest x2, one x2, ayu-mirage, dracula, kanagawa, nightfox). |
| `modules/tmux-helper/` | Go helper module (`my.tmuxHelper`), `package.nix`, `install-script.nix` (darwin-only `/usr/local/bin` install for BeyondTrust). |

Helper subcommands (`src/main.go`):
- **Implemented:** `status` (uptime-fmt, user-host [ssh-aware, 30s atomic file cache], git-branch, nix-shell, llm, battery [10-cell heart bar, per-theme gradient]), `clipboard` (pbcopy / clip.exe+UTF-16LE / wl-copy / xclip / xsel), `theme` (apply/cycle/list), `picker` (sessions/windows/panes/projects via fzf display-popup), `navigate` (vim-aware C-h/j/k/l), `maximize-pane`, `toggle-mouse`, `reload`, `clear-history`, `fpp`, `urlview`/`urlscan`, `open-file` (path[:line[:col]] → emacsclient, $EDITOR fallback), `version`.
- **Still stubs (`errNotImpl`):** `new-window-ssh`, `split-window-ssh`, `apply-theme` (superseded by `theme apply`), `jump`.

Key bindings (prefix C-a): `r` reload · `C-l` clear-history · `T` theme cycle ·
`s/w/./P` fzf pickers · `F` fpp · `U` urlview · `+` maximize · `m` mouse ·
`j/J` jump-to-char (pure-tmux v1) · copy-mode-vi `y` clipboard, `o` open-file ·
`-`/`_` splits in cwd · global `C-h/j/k/l` vim-tmux-navigator. Theme applied
at conf load via `theme apply <preset>`; runtime choice persists in
`@tmux_theme_preset` for the server lifetime only.

## 2. Graduation criteria — retrospective and leftovers

Satisfied before Phase 9 (per git history): daily use on the experimental
socket (Phases 2–7, ~Apr 2026), gpakosz visible parity (theme + 38 binds,
Phase 4/5.1), SSH-aware status (Phase 6), stable enough to drop the
kill-switch (9.5). Hardening landed post-cutover (`fdcf6df`, 2026-06-10):
`#{q:}` quoting on user-influenceable format args, darwin `ps` fixes,
atomic ssh cache writes, exec timeouts.

Open items that survived graduation:

- [ ] **Corp-Mac BeyondTrust decision** — `my.tmux.preferSystemPath` exists
      but is never set true for user `888973` in `flake.nix`. Decide:
      set it + run `nix run .#tmux-helper-install` (re-run on every helper
      bump), or delete the option if EPM never flags the /nix/store path.
- [ ] **Stub subcommands** — implement or delete `new-window-ssh`,
      `split-window-ssh`, `jump` (easymotion labels; deferred ~150 LOC per
      conf comment); delete the redundant `apply-theme` stub.
- [ ] **Theme persistence** — runtime `prefix-T` choice dies with the tmux
      server; only `my.tmux.theme.preset` + `hms` persists. Acceptable?
- [ ] **Stale references** — `conf-experimental.nix` header still mentions
      the removed `my.tmux.useHelper`; `apps.tmux-experimental` description
      still says "parallel to gpakosz daily driver"; file could be renamed
      `conf.nix`. (Cosmetic; other agents own flake.nix.)
- [ ] **Intentional gpakosz deviations to confirm, not regress:**
      `prefix-C-l` = clear-history (next-window only via `n`),
      `prefix-P` = project picker (choose-buffer moved to `B`),
      `prefix-e` opens the nix module in $EDITOR (no live source-reload —
      conf is read-only in /nix/store).

## 3. How to trial future config changes (parallel socket)

```sh
nix run .#tmux-experimental    # tmux -L experimental -f <generated conf>
```

- Socket `-L experimental` is fully isolated from the default server; the
  daily driver is untouched. Note the app pins `defaultThemePreset =
  "molokai"` while the daily config uses `nord` (flake.nix), so colors
  differing at launch is expected.
- Cycle themes with `prefix-T`; verify pickers (`prefix-s/w/./P`) and
  copy (`copy-mode-vi y`) on each platform.
- Where issues surface: status-bar `#()` segments going blank/`<'...'>` =
  helper crash in the status path (run the failing
  `tmux-helper status ...` by hand); bind failures appear via
  `display-message`; clipboard issues differ per backend (clip.exe vs
  pbcopy vs OSC 52 over ssh).

## 4. How to graduate a trialed change

1. Edit `conf-experimental.nix` / helper source; test on the experimental
   socket (step 3) and run `go test`/`go vet` via `nix flake check`.
2. `hms` — the daily driver consumes the same conf function, so the change
   lands automatically; `prefix-r` reloads running sessions.
3. On the corp Mac with `preferSystemPath = true` (if adopted): re-run
   `nix run .#tmux-helper-install` after any helper change.

## 5. Decision log

| Date | Criterion / decision | Status |
|---|---|---|
| 2026-04-29 | Phase 9: cutover daily driver to helper-driven config (`bef7cf9`) | done |
| 2026-04-29 | Phase 9.5: remove `useHelper` kill-switch (`2953a51`) | done |
| 2026-06-10 | Injection + portability hardening (`fdcf6df`) | done |
| — | BeyondTrust `preferSystemPath` on corp Mac | open |
| — | Implement-or-delete stub subcommands | open |
| — | Clean up stale "experimental"/gpakosz naming | open |
