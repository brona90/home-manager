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
| Phase | **3 — Bindings**. The discoverable `SPC` leader menu, on Doom's keys. |

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
- [x] **Bindings**: `lisp/my-bindings.el`. 14 named prefixes and ~150 named
      leader keys on Doom's key choices, every one of them showing a
      human-readable name in the which-key popup — the whole point of a leader
      key, and the thing that was still missing. Gate: a real daemon walks the
      override map and asserts `fboundp` on every command it reaches (738
      reachable, 0 void) and that no key or prefix renders as a raw symbol
      (490 named, 0 unnamed). What is still absent is the long tail behind
      features this config does not have — see below
- [ ] Two weeks as `emv` without reaching for `em`

## Deliberate differences from Doom — bindings

Every one of these is a key where Doom's command does not exist outside Doom.
The key is kept so the finger lands somewhere sane; the behaviour differs.

| Key | Doom | Here | Difference that will be noticed |
|---|---|---|---|
| `SPC c e` | `+eval/buffer-or-region` | `my/eval-buffer-or-region` | **elisp only.** Doom dispatches on major mode through quickrun; this evaluates as Emacs Lisp or not at all |
| `SPC c d` / `c D` | `+lookup/definition`, `+lookup/references` | `xref-find-definitions`, `xref-find-references` | no dumb-jump/online fallback chain — with no LSP and no tags, xref just fails |
| `SPC c k` | `+lookup/documentation` | `eldoc-doc-buffer` | point-local docs only; no docset or online lookup |
| `SPC c f` | `+format/region-or-buffer` | `eglot-format` | needs a live language server; there is no format-all equivalent here |
| `SPC f D` | `doom/delete-this-file` | `delete-file` | prompts for a filename instead of acting on the current buffer |
| `SPC s l` / `s c` | `link-hint-open-link`, unbound | `avy-goto-line`, `avy-goto-char-timer` | different feature entirely. link-hint is not in the package set and avy had no leader key; these two free keys went to the tool that is present |
| `SPC b K` | `doom/kill-all-buffers` | *unbound* | `SPC b O` (`my/kill-other-buffers`) is the nearest thing, and it spares non-file buffers |
| `SPC m r` | refile sub-prefix | `org-refile` directly | Doom's `SPC m r r`. The rest of that sub-menu is `+org/` commands that do not exist here |
| `SPC o a` | `org-agenda` (phase 2) | sub-prefix; agenda is `SPC o a a` | this is Doom's actual layout — phase 2 was the deviation. `SPC o A` and `SPC n a` also reach it |
| `SPC o l` | *(llm prefix)* | *moved:* store-link is now `SPC n l` | phase 2 put `org-store-link` on `SPC o l`, which is not a Doom key |

Unbound rather than repurposed, because the feature is not here at all:
`SPC TAB` (workspaces), `SPC ~` (popups), `SPC d` (dape), `SPC l` (crdt),
`SPC r` (ssh-deploy), snippets, treemacs, docsets, `SPC t z` (zen).

`SPC m` is still structurally global rather than mode-local — it is reached
through an evil *intercept* map, so `org-mode-map` is never consulted once
`SPC` resolves. A genuinely mode-local localleader needs a dispatcher keymap
and is not done. In practice the org commands under it error clearly outside
an org buffer.

## Deliberate differences from Doom — org

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
