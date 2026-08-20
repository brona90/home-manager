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
| Phase | **2 — Org**. Agenda, capture, refile, dashboard, Google Calendar. |

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

- [x] **Org**: agenda, capture, refile, the daily dashboard. Ported verbatim
      from the `after! org` block; `evil-org` carries the folding and motions
- [ ] **org-gcal**: three calendars and sops credentials are wired and load
      (see "Deliberate differences" below for the two things that are not
      copies of Doom). What is **not** done is the part that matters: fetch
      once and diff `gcal*.org` against what Doom produces. Whether it errored
      is not the test — a fetch that silently writes half a calendar exits 0
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

## Deliberate differences from Doom

Two, both in `lisp/my-org.el`. Neither is an omission.

**No 30-minute background fetch timer.** Doom re-fetches every 30 minutes. Two
daemons doing that would write `~/org/gcal*.org` underneath each other, and
whichever has the buffer open hits "file changed on disk" — turning a trial
config into a data-loss question about real calendar entries. Fetch here is
`SPC m G f`, by hand. Restore the timer from `doom.d/config.el` at graduation,
when Doom stops.

For the same reason: **do not run a vanilla fetch while Doom has a `gcal*.org`
buffer open.** That is the one way this parallel instance can damage something
the daily driver owns.

**The OAuth token store is a plain `0600` file, not a GPG-encrypted plstore.**
`~/.local/state/emacs/oauth2-auto.eld`, separate from Doom's, so both keep
working. The reasoning is written out at length in `lisp/my-secrets.el`; the
short version is that Doom's store is encrypted to a key with no passphrase
whose private half sits at `0600` on the same disk, so the encryption was
never adding protection over the file mode. Encrypting to the YubiKey key
instead is not an option while the fetch has to run unattended — that trade is
real and it was made knowingly.

To authorise this Emacs without redoing the browser flow, run
`M-x my/oauth2-import-from-plstore` once and accept the default path. It reads
Doom's store; it does not move it. That command is the only thing in this
config that touches GPG, and it never runs on its own.

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
- Restore the 30-minute `org-gcal` fetch timer (see above)
- Retire the passphrase-less GPG key `050C399D3A6B013DD2C93F899BC379782DFE1930`
  once `~/.config/org-gcal/oauth2-auto.plist` is gone: delete the key from the
  keyring, drop its sops secret and the sops-nix decrypt block, and revoke it.
  Nothing else uses it — that is the "one secret system" this was for, and it
  is not finished until the key is actually gone rather than merely unused
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
