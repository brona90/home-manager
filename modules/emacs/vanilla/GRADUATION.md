# Vanilla Emacs — graduation

Mirrors `modules/tmux/GRADUATION.md`: a parallel instance that runs beside the
daily driver until it earns the default slot.

## Current state

| | |
|---|---|
| Daily driver | **Doom** (`my.emacs.flavor = "doom"` in `flake.nix`) |
| Vanilla | second daemon, socket `vanilla`, Linux only |
| Reach it | `emv` (GUI-or-TTY), `emvt` (TTY), or `emacsclient -s vanilla` |
| Try it without `hms` | `nix run .#emacs-vanilla` |
| Base Emacs | `pkgs.emacs` 30.2 on **every** platform |
| Config | `modules/emacs/vanilla/config/`, linked to `~/.config/emacs` |
| Phase | **1 — scaffold**. Opens files, completes, evil, magit. No Org yet. |

Doom is untouched. Nothing about the daily driver changes until `flavor` flips.

## How to trial

```sh
nix run .#emacs-vanilla     # throwaway foreground Emacs, no daemon, no hms
hms && emv                  # the real parallel daemon
systemctl --user status emacs-vanilla
```

`nix run .#emacs-vanilla` points `--init-directory` at a **read-only store
path** on purpose. That run *is* the test that `early-init.el` has redirected
every writable path — `eln-cache`, `custom.el`, `auto-save`, `recentf`,
`transient` — out of `user-emacs-directory`. If it tries to write into the
store, the redirect is incomplete: fix `early-init.el`, do not make the
directory writable.

## Graduation criteria

Not yet met. In rough order of how much they hurt when missing:

- [ ] **Org**: agenda, capture, refile, the daily dashboard
- [ ] **org-gcal**: three calendars, sops credentials, the passphrase-less GPG
      key, save-after-fetch advice, the 30-minute timer. Verify by fetching and
      diffing `gcal*.org` against what Doom produces — not by whether it errored
- [ ] **claude-diff.el** ported, with the Claude popup as a **bottom** window.
      A side window breaks it: `claude-diff-show` calls `delete-other-windows`,
      which cannot delete a side window, and Doom's popup module was silently
      supplying a shim
- [ ] **LilyPond**: mode loading, the flycheck checker, async build-on-save.
      This exists only in `config.el` because the Doom module could not build
      under nix-doom — there is no module behind it to fall back on
- [ ] **Languages**: eglot + treesit for the ten in use
- [ ] **Bindings**: enough of `SPC` that muscle memory stops misfiring. The
      long tail, and the thing that decides whether this took a weekend or a
      month
- [ ] Two weeks as `emv` without reaching for `em`

## Graduating

One word in `flake.nix`:

```nix
my.emacs.flavor = "vanilla";
```

Then vanilla owns the default socket and `em`, `EDITOR`, `emacs-doctor` and the
emacs MCP server follow it automatically — they read `primaryPackage`, not
`package`. Doom does not disappear; it becomes `emacsclient -s doom`, reachable
as `emd`/`emdt`. Rollback is the same word.

Also flip `X-RestartIfChanged` to `false` on the vanilla unit at that point.
It is `true` today because picking up a new config immediately is the whole
point while iterating, and there are no precious buffers in it yet — that stops
being true the day it becomes the daily driver.

## Retiring Doom (after graduation)

- Delete `modules/emacs/doom.d/` and the `doom-emacs` flake input
- Restore `--all-systems` to `nix flake check` — the IFD is what forced its
  removal
- Drop the `android-mode` and `org-pdftools` disables from `packages.el`, and
  the codeberg/IFD workarounds from `ci.yml`. The uncached-fetch flakiness that
  fails builds on a transient GitHub 408 goes with them
- Drop the nix-doom row from `dev-disk`
- Rewrite the README's first table row

## Notes

**Emacs 30.2 everywhere, deliberately.** `emacs-overlay` offers 31.x and it is
cached on Linux — but its hydraJobs cover `x86_64-linux` and `aarch64-linux`
only, so `emacs-unstable` on either Mac is an uncached source build on the
least-tested stdenv in the tree. Taking 31 on Linux alone would introduce a
skew where 31-only code builds fine and fails on the Macs. Emacs 31.1 releases
2026-08-24; moving to it is a deliberate one-line change in `package.nix`, made
once, after this config is stable.

**The package list is explicit, not parsed.** `emacsWithPackagesFromUsePackage`
cannot handle unicode in the config it parses, and this elisp uses box-drawing
rules. A silent mis-parse is worse than a hand-maintained list.

**`recursive = true` on `xdg.configFile."emacs"` is load-bearing.** Without it
the directory becomes one store symlink and Emacs can never write into
`user-emacs-directory`.
