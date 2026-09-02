# Emacs — the design

This is the only Emacs. It replaced Doom, which it ran beside on a second
socket for four phases before taking the default one; this file was that
trial's `GRADUATION.md` and is now the design document for what came out of
it. What is still here is the reasoning — every place this config does
something other than the obvious thing, and why. What was removed is the
checklist, the phase table and the rollback instructions, because the
graduation happened.

Anything left for a **human** after the retirement — the passphrase-less GPG
key, `~/.local/share/nix-doom`, the sops entry — is in
[`../RETIRING-DOOM.md`](../RETIRING-DOOM.md), not here.

Several files under `config/lisp/` say they were ported from
`modules/emacs/doom.d/config.el`. That path no longer exists; the statements
are provenance, not directions, and `git log -- modules/emacs/doom.d` has the
originals. They are left as written because "this was transcribed from X, with
these three changes" stops being checkable the moment X is renamed out of the
sentence.

## What it is

| | |
|---|---|
| Base Emacs | `pkgs.emacs` 30.2 on **every** platform |
| Package set | explicit list in `package.nix`, from the `emacs-overlay` MELPA/ELPA snapshot |
| Config | `modules/emacs/vanilla/config/`, linked to `~/.config/emacs` |
| Reach it | `em` (GUI-or-TTY), `emt` (TTY), or a bare `emacsclient` — the DEFAULT socket |
| Daemon | `systemctl --user status emacs`, or launchd on darwin |
| Try a build without `hms` | `nix run .#emacs-vanilla` |
| Gate | `bash modules/emacs/vanilla/verify.sh` — lints, builds, then asks a real daemon |
| Theme | `gruvbox-dark-medium` from upstream `gruvbox-theme` |

The daemon unit exports `EMACS_SOCKET_NAME=%t/emacs/server`. That is what makes
a Claude session running in a vterm inside the daemon fire its hooks at *that*
daemon: Emacs never exports that variable to subprocesses, it is read by the
`emacsclient` binary, and `modules/claude-code.nix` has passed
`-s "$EMACS_SOCKET_NAME"` since #17 with nothing setting it. The unit sets it
explicitly even though the unset fallback already resolves correctly — see the
comment in `modules/emacs/default.nix` for why that was not left to chance.

## Running it

```sh
nix run .#emacs-vanilla     # throwaway foreground Emacs, no daemon, no hms
hms && em                   # the real thing
systemctl --user status emacs
```

`nix run .#emacs-vanilla` points `--init-directory` at a **read-only store
path** on purpose. That run *is* the test that `early-init.el` has redirected
every writable path — `eln-cache`, `custom.el`, `auto-save`, `recentf`,
`transient` — out of `user-emacs-directory`. If it tries to write into the
store, the redirect is incomplete: fix `early-init.el`, do not make the
directory writable.

## What it covers

Built in four phases, each one gated by `verify.sh` against a real daemon. In
rough order of how much each would hurt if it broke:

- **Org**: agenda, capture, refile, the daily dashboard. Ported verbatim
      from the `after! org` block; `evil-org` carries the folding and motions
- **org-gcal**: three calendars, sops credentials, and a 30-minute background
      fetch. The acceptance test was not "did it error" — a fetch that
      silently writes half a calendar exits 0 — but a real fetch diffed
      against Doom's output: 243 entries conserved across live and archive,
      lossless. See "Deliberate differences — org" for the token store, which
      is the one place this is not a copy of Doom
- **claude-diff.el** ported to `lisp/claude-diff.el`, required **eagerly**
      because the PermissionRequest hook `--eval`s into a daemon that may never
      have loaded `claude-code.el`, and `--eval` cannot autoload a function
      with no stub. The Claude popup is a **bottom** window, and the caller
      selects `window-main-window` before deleting — see "Deliberate
      differences — Claude" for why both halves are needed and what the third
      option would have cost. `claude-code` is the nixpkgs package (the same
      `yuya373/claude-code-emacs` Doom runs), `SPC l` is Doom's eleven keys,
      and `projectile` comes with it as private plumbing that takes no key
- **LilyPond**: `lisp/my-lilypond.el`. Mode loading through a casing shim,
      the flycheck checker **ported to flymake**, async build-on-save, and an
      explicit display rule for the failure buffer that Doom's popup manager
      used to place. The gate runs a real `lilypond` over four sample files
      and checks the diagnostics, because the interesting half of that checker
      is the case where 2.26 emits a warning with **no column**
- **Languages**: `lisp/my-lang.el`. 21 file types checked in a live daemon —
      every one lands in the intended major mode, and every one that has a
      tree-sitter mode in Emacs 30.2 has a live parser. 17 grammars come from
      Nix (an explicit list; see `package.nix` for why it is not
      `withAllGrammars`). eglot gets three additions and no more: a `taplo`
      contact for `toml-ts-mode`, a pin to `pyright-langserver` for Python
      (pyright *and* ruff are installed, so `M-x eglot` otherwise prompts and
      `eglot-ensure` silently picks one), and a `nil` contact for
      `nix-ts-mode` — that last one because the assumption that `nix-ts-mode`
      calls `derived-mode-add-parents` (which is what would make eglot's
      `nix-mode` entry match it) is **false** in `nix-ts-mode 20260705.1600`.
      `haskell-ts-mode` 1.3.5 does make that call and needs nothing. The gate
      found the difference; the design had not
- **Bindings**: `lisp/my-bindings.el`. 14 named prefixes and ~150 named
      leader keys on Doom's key choices, every one of them showing a
      human-readable name in the which-key popup — the whole point of a leader
      key, and the thing that was still missing. Gate: a real daemon walks the
      override map and asserts `fboundp` on every command it reaches (738
      reachable, 0 void) and that no key or prefix renders as a raw symbol
      (490 named, 0 unnamed). What is still absent is the long tail behind
      features this config does not have — see below
- **Popups**: `lisp/my-popups.el`. Doom's `:ui popup` is ~1400 lines; this
      is ~60 and **no packages** — `window-sides-slots`, four
      `display-buffer-alist` rules and `SPC ~`. `popper` and `shackle` were
      both evaluated and rejected. Three Doom behaviours are deliberately not
      reproduced (`vslot`, `:ttl`, ESC-to-close) and each is written up below
      with its reason. The gate displays a real `*Help*` buffer on the daemon's
      real frame and asserts the side window, the height, the missing mode
      line, the weak dedication, and the `SPC ~` round trip **in both
      directions** — which is how it caught that `mode-line-format` is not in
      `window-persistent-parameters` and was silently lost on restore
## Deliberate differences from Doom — languages

**`eglot-ensure` is hooked only where the server is actually installed.** The
17 modes that get it were checked against `~/.nix-profile/bin`, not against what
would be nice. C, C++, CMake, Fortran and LaTeX get a working major mode and no
eglot hook, because `clangd`, `cmake-language-server`, `fortls` and `texlab` are
not installed. A hook with no server behind it logs a failed connection on
*every* `find-file` in that language, which is how people learn to ignore eglot
errors. Install the server, then add the hook — in that order. The gate asserts
both halves: every hooked mode resolves to a contact, and none of the five
server-less ones is hooked.

**Five grammars are deliberately absent** from `package.nix`: markdown, latex,
commonlisp, elisp and fortran. There is no `markdown-ts-mode`, `latex-ts-mode`,
`commonlisp-ts-mode`, `elisp-ts-mode` or `fortran-ts-mode` in Emacs 30.2 or in
the package set — `markdown-mode`, AUCTeX, `sly`, `lisp-mode` and `fortran-mode`
are font-lock modes. Those grammars would grow the closure and never create a
parser. `treesit-parser-list` being nil in a `.md` or `.tex` buffer is the
correct answer, and the gate's expectation table says so in as many words so
that nobody "fixes" it.

**AUCTeX is reached through a shim, `my/LaTeX-mode`, and that is not tidiable.**
Emacs's dumped loaddefs ships both `(defalias 'LaTeX-mode #'latex-mode)` and a
`major-mode-remap-defaults` entry for it, and `autoload` does nothing when a
symbol is already `fboundp`. Every deferred route through the name `LaTeX-mode`
therefore resolves to the *built-in* `latex-mode` and looks exactly like AUCTeX
not being installed. Four variants were measured before the shim was written.

**`.mjs` and `.cjs` had no `auto-mode-alist` entry at all** — anywhere in Emacs
30.2. They opened in `fundamental-mode`. That is fixed here, and it is the kind
of thing that stays invisible until someone opens an ESM config file.

**`go.mod` opened in `m2-mode`** (Modula-2), because `files.el` matches
`\.mod\'`. Also fixed here.

Not covered at all, and not pretended otherwise: CSS, HTML, C#, PHP, Ruby,
Elixir. Emacs 30.2 has a `-ts-mode` for each and servers exist for several, but
none of them is in use, and an entry per language that nobody opens is a list
that rots silently. Adding one is a `:mode` line, a grammar in `package.nix` and
a row in the gate's table.

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
`SPC TAB` (workspaces), `SPC d` (dape), `SPC r` (ssh-deploy), snippets,
treemacs, docsets, `SPC t z` (zen).

`SPC ~` **is** bound, and it is the one key on that list that came back. Doom
puts `+popup/toggle` there; here it is `window-toggle-side-windows`, which is
that command and `+popup/restore` in one. See "Deliberate differences —
popups".

`SPC l` is **claude**, as in Doom. Doom's `SPC l` is the crdt module, which is
not in this package set, so the prefix was free and Doom's own eleven Claude
keys — four session, seven diff-review — transfer unchanged.

`SPC m` is still structurally global rather than mode-local — it is reached
through an evil *intercept* map, so `org-mode-map` is never consulted once
`SPC` resolves. A genuinely mode-local localleader needs a dispatcher keymap
and is not done. In practice the org commands under it error clearly outside
an org buffer.

## Deliberate differences from Doom — popups

`lisp/my-popups.el`. Doom's `:ui popup` is a ~1400-line popup **manager**; this
is ~60 lines of settings and **zero packages**, because the 80% that matters is
three Emacs 30 built-ins.

**What is there:**

| | |
|---|---|
| `window-sides-slots` | `(nil nil nil 1)` — **one** bottom popup, ever |
| `*Help*`, `*Apropos*`, `*eldoc*`, `*info*` | bottom side window, 0.42 of the frame, no mode line, **selected** (Doom's `:select t`, via the Emacs 30 `body-function` entry) |
| `*Flymake diagnostics for …*` | same, 0.3, selected — a list you cannot move point into is a picture of a list |
| `*Messages*`, `*Warnings*`, `*Compile-Log*` | same, 0.3, `post-command-select-window . nil` (Doom's `:select nil`) |
| `*compilation*` | same, 0.3, not selected, and the **one popup that keeps its mode line** — compilation state (`run`, `exit [1]`) lives in `mode-line-process` and nowhere else |
| `SPC ~` | `window-toggle-side-windows` — Doom's `+popup/toggle` **and** `+popup/restore` in one preloaded, interactive command |

**Two packages were evaluated and rejected**, and both will be proposed again:

- **`popper`** buys popup *cycling* and per-project grouping and nothing else
  this lacks — and it does not solve the side-window problem people reach for
  it to solve, because `popper-display-popup-at-bottom` calls
  `display-buffer-in-side-window` itself. It also walks straight into this
  config's characteristic trap: only `popper-mode` carries an autoload cookie,
  so `popper-toggle`, `popper-cycle` and `popper-raise-popup` would be **void
  on the keypress**, and `popper-echo-mode` lives in a separate file nothing
  loads. Three extra `use-package` forms to get less than `SPC ~` gives free.
- **`shackle`** is two commits in six years and covers only the part
  `display-buffer-alist` already does well in Emacs 30.

### The three things Doom does that this cannot, and does not pretend to

These are **omissions with reasons**, not oversights. Each one is a feature of
Doom's *manager*, and there is no manager here.

1. **The `vslot` axis — two stacked bottom popups.** Emacs's side windows put
   two bottom slots **side by side**, not stacked (`window-sides-vertical` is
   nil, and full-width bottom popups are the point). So a second slot would
   give two 40-column popups on an 80-column frame rather than Doom's two
   stacked ones. The answer here is `window-sides-slots` bottom = **1**: a new
   popup *replaces* the old one. Reuse is the better failure mode, and it makes
   the omission a decision rather than a gap. Reproducing `vslot` properly
   means writing a layout manager, which is the 1400 lines.

2. **`:ttl` — the buffer-kill timer.** Not ported, and *"not worth it until
   measured"* is the honest form of that. With one bottom slot the **visible**
   clutter `:ttl` exists for cannot happen. What is left is buffer-*list*
   clutter, and `*Help*`, `*Apropos*` and `*eldoc*` are single reused buffers,
   not one per invocation — the only things that really accumulate are
   `*Flymake diagnostics for `x'*` (one per buffer), which `SPC b O` already
   answers. Against that: a wall-clock timer that kills buffers is the one
   thing in this config that could destroy work, it is the first piece of
   background state that mutates buffers, and it is untestable by this gate
   without sleeping in it. **What would change the answer:** if `buffer-list`
   after a two-week session is more than ~20% transient buffers, revisit.

3. **ESC-to-close.** Doom closes popups from `doom-escape-hook`. There is no
   such hook here and nothing to hang one on: grepping `my-bindings.el` for
   `escape`, `ESC` and `keyboard-quit` returns **zero** hits, so ESC is plain
   `keyboard-quit`. `q` in the popup and `SPC ~` are the ways out. Adding an
   ESC hook means inventing a dispatcher, which is the manager again.

### Three more things deliberately not done

- **`no-other-window` is not set on the popups**, though Doom sets it on every
  one. Doom can afford it because `+popup/other` exists to jump *into* a popup;
  there is no such command here and no manager to hang one off, so it would
  leave a popup you can see and cannot select — unscrollable, unquittable,
  mouse-only. The gate asserts the `*Help*` popup **is** reachable by
  `other-window`, so this is a checked invariant rather than a note.
- **`no-delete-other-windows` is not set either**, though it is the obvious
  next built-in (window.el:4387-4402). Putting it on these popups is exactly
  option (c) that "Deliberate differences — Claude" below considered and
  rejected: the popup would survive `claude-diff--show-1`'s
  `delete-other-windows`, its "bottom third" would become a third of the *main
  area*, and the Claude buffer would be on screen twice. The gate asserts a
  popup **is** cleared by `delete-other-windows` from the Claude window.
- **`*Backtrace*` gets no rule**, unlike Doom. The Emacs debugger enters
  `recursive-edit` in that window and drives selection itself; a dedicated side
  window plus a selection override is a change this gate cannot exercise, and
  untestable window surgery on the debugger is a bad trade. **`helpful` gets no
  rule either** — the package is not in `package.nix`, so the branch would be
  dead. Add it in the commit that adds the package, not before.

### How it composes with the two rules that were already here

`display-buffer-alist` already had two entries, and **both deliberately produce
ordinary windows**: `"^\\*claude:"` (my-claude.el) and `"^ \\*lilypond: "`
(my-lilypond.el). All four popup regexps are anchored with `` \` `` and are
disjoint from both. `my-popups` is `require`d **first** in `init.el`, so —
because `add-to-list` prepends — its general rules end up *after* those two
specific ones in the alist. The gate proves the composition rather than
asserting it: with a popup already open it displays a `*claude:*` buffer and a
` *lilypond: *` buffer and reads `window-side` off each.

**which-key shares the slot, and that is fine.** `which-key-popup-type` is
already `side-window` with `which-key-side-window-slot` 0 at the bottom — the
same window. It swaps its own buffer in on every leader prefix and restores the
window configuration afterwards (`which-key-preserve-window-configuration` is
t). This is why the popups are `(dedicated . side)` and **not** `(dedicated
. t)`: `t` is *strong* dedication, and a strongly dedicated window is one
`set-window-buffer` away from an error. The value `side` is also the only value
`window--display-buffer` re-applies to a *reused* window (window.el:7381),
which is what keeps the popup dedicated as buffers rotate through the slot.

## Deliberate differences from Doom — Claude

**The Claude window is an ordinary bottom window, not a side window, and the
caller guards too.** `claude-diff--show-1` calls `delete-other-windows`, which
signals *"Cannot make side window the only window"* (window.el:4381) when the
selected window is a side window — every time the hook fires while you are
sitting in the Claude popup. Doom's `+popup` module shimmed this with a
`delete-other-windows` window parameter. Two fixes, doing different jobs:

- `display-buffer-at-bottom` makes the Claude window deletable, which is what
  the **layout** needs: claude-diff clears the frame and rebuilds three panes.
- `claude-diff--select-main-window` makes the **call** legal from anywhere,
  which matters independently — `which-key-popup-type` is `side-window` here.

The third option, `(window-parameters . ((no-delete-other-windows . t)))` on a
side window, was **rejected, not overlooked**. It is not a drop-in: with the
Claude window surviving, `claude-diff--show-1` still splits a bottom third and
puts the Claude buffer in it, so the buffer would be on screen twice. Taking it
means redesigning the layout so claude-diff builds *around* a persistent Claude
window — a reasonable design, and one `window-toggle-side-windows` would give a
free show/hide for — but it cannot be tested from here (that path needs a live
Claude vterm in this daemon and a real GUI frame), and rewriting layout code on
the one untestable path is where bugs ship. The full argument is in
`lisp/my-claude.el`.

**The `claude-code-normalize-project-root` advice is `:filter-args`, and the
obvious `:filter-return` does not work.** Upstream *signals* a `user-error` on
a nil project root rather than returning nil, and a `:filter-return` advice
never runs when the advised function signals — so it is dead code against this
upstream. Measured, not reasoned: with the `:filter-return` version installed,
`(claude-code-normalize-project-root nil)` still signals. It was correct
against an older claude-code that returned nil, and it stopped working silently
when upstream tightened the guard. `SPC l l` from `*scratch*` depends on the
fix, and the gate asserts the **result** — a string comes back — rather than
which combinator is installed.

**`projectile` is installed and enables nothing.** It is a hard dependency of
seven of claude-code's files (`projectile-project-root`,
`projectile-project-files`, `projectile-project-type` — project.el has no
analogue for the last two). It is not a mode here and it takes no key: `SPC p`
remains project.el's `project-prefix-map`.

**Doom's `:quit nil` / `:ttl nil` / `:modeline t` have no counterpart** and
need none — they are popup-*manager* concepts, and vanilla has no manager.

**Not verified, and cannot be from here:** the hook end-to-end. Proving the
diff actually appears needs a live Claude session in a vterm inside the vanilla
daemon with a GUI frame. What is proved is every precondition: claude-diff is
loaded, `claude-diff-from-hook` is a real function, the unit exports
`EMACS_SOCKET_NAME`, the window is not a side window, and
`delete-other-windows` does not signal from it.

## Deliberate differences from Doom — LilyPond

**`lilypond-mode`, lowercase.** 2.26 renamed every symbol ("Change all
prefixes to lowercase to follow the Elisp convention"), and the Doom config
hardcoded `LilyPond-mode` for two years — during which `auto-mode-alist`
pointed at a void function, the checker was `:modes` a mode that never
activated, and the build hook was added to a hook that never ran. All three
silently dead. `.ly` here goes to a shim, `my/lilypond-mode`, that dispatches
on whichever casing the loaded file defines, because Homebrew's lilypond on
darwin moves on its own schedule.

**flycheck → flymake, and it is registered but NOT enabled.** This is the one
place vanilla deliberately does less than Doom. Doom's `:checkers syntax`
turns flycheck on globally, so every save ran lilypond **twice** — once for the
checker and once for the build. Vanilla enables flymake nowhere by default
(only eglot does, and eglot never manages a `.ly`), so the default here is one
lilypond per save: the build, which produces the PDF you are looking at and
whose failure buffer carries lilypond's own error text. The backend is still on
`flymake-diagnostic-functions` in every LilyPond buffer, so `SPC t f` turns
inline diagnostics on for anyone who wants them and accepts the second process.
The gate asserts `flymake-mode` is *off*, so a future "helpful"
`(flymake-mode 1)` shows up as a gate change rather than as silent CPU.

**The column is optional on warnings.** 2.26 emits
`file.ly:1: warning: no \version statement found` with **no column**; errors do
carry one. A pattern requiring a column drops every warning. Both branches are
run for real by the gate against real files.

**The temp file is compiled with `-I <source dir>`.** Without it a relative
`\include` fails from `/tmp` and lilypond cascades into three errors that are
not in the user's file — measured, and the gate has a sample file for it.

**pdf-tools is not in the package set**, so the PDF-refresh-after-build lands
in `doc-view-mode`, not `pdf-view-mode`. `revert-buffer` still re-renders; what
is lost is pdf-view's scroll-position preservation, so the view jumps back to
page one on each rebuild. Adding pdf-tools is a line in `package.nix` and
poppler in the closure — a decision, not an oversight, and not taken here.

## Deliberate differences from Doom — org

One, in `lisp/my-org.el`, and it is not an omission.

**The 30-minute background fetch timer is back, and it is why the gate does
not fetch.** It was withheld for the whole parallel period: two daemons on that
timer would have written `~/org/gcal*.org` underneath each other, and whichever
held the buffer would have hit "file changed on disk" — a data-loss question
about real calendar entries rather than a preference. One daemon means one
writer, so the timer was restored with Doom's timings (90s after start, then
every 30 minutes).

That reasoning did not evaporate, it moved: `verify.sh` starts a **third** real
daemon out of the store, and a gate daemon on that timer would recreate the
two-writer case against the live one. `my/org-gcal-fetch-inhibit` is set from
the environment variable `verify.sh` already exports, and section (i) of the
gate asserts **both** that the timer exists and that the inhibit is on — either
check alone is satisfiable by the bug the other catches.

**The OAuth token store is a plain `0600` file, not a GPG-encrypted plstore.**
`~/.local/state/emacs/oauth2-auto.eld`. It was a separate path from Doom's so
both could keep working through the parallel period; it is now simply the
store. The reasoning is written out at length in `lisp/my-secrets.el`; the
short version is that Doom's store was encrypted to a key with **no
passphrase** whose private half sat at `0600` on the same disk, so the
encryption was never adding protection over the file mode — and it cost a
certify-capable, always-unlocked key sitting ultimately trusted in the keyring.
Encrypting to the YubiKey key instead is not an option while the fetch has to
run unattended: that trade is real and it was made knowingly, and it is the
reason the fetch is allowed to be a background timer at all.

`M-x my/oauth2-import-from-plstore` reads Doom's plstore into the `.eld`. It
was the migration path and it has already been used; it is kept only as the
recovery route from a lost `.eld`, and it stops working the moment the
passphrase-less key leaves the keyring (see `../RETIRING-DOOM.md`, step 3).
That command is the only thing in this config that touches GPG, and it never
runs on its own.

## What retiring Doom changed outside this directory

Recorded because each of these was a workaround whose *cause* is now gone, and
a workaround with no visible cause is the kind of thing that gets reinstated.

- **`my.emacs` collapsed to one package.** The `flavor` enum, the
  `primaryPackage` resolver, the second pair of client wrappers (`emd`/`emdt`)
  and the hand-rolled `emacs-<flavor>` systemd unit are deleted rather than
  left as an enum with one value. `modules/emacs-mcp.nix` and
  `modules/emacs-doctor/default.nix` read `my.emacs.package` again; each
  carries a note naming itself as a site that would have to follow the primary
  if a second Emacs ever came back, and `modules/orrery-mcp/default.nix` carries the
  note that it is the one that would not.
- **`nix flake check --all-systems` is back**, in `ci.yml` and
  `update-flake.yml`. It was dropped because nix-doom-emacs-unstraightened's
  import-from-derivation sets `allowSubstitutes = false` on its intermediate
  derivations, so *evaluating* a darwin config required *building* darwin
  derivations, which a Linux runner cannot do. No IFD, no problem — verified
  by running it, not assumed. It reaches the Darwin home configurations too,
  which is not obvious: `flake check` has no idea what `homeConfigurations`
  is, but `perUserPackages` mirrors each one into
  `packages.<system>.home-<username>`, and those get walked.
- **The `check` job's retry loop went with it.** That loop existed because the
  same IFD refetched 528 elisp sources uncached, from GitHub, GitLab and
  codeberg, on every run — PRs #20 and #21 both died inside a minute on
  `gitlab.com/sawyerjgardner/demap.el`, a package referenced nowhere in this
  repo and pulled in by Doom's module set. `nix flake check` now substitutes
  from the binary caches like everything else. The retries on `eval-darwin`
  and `build-home` **stayed**: those jobs build real closures over the network
  and their flakiness was never Doom-specific.
- **`doom-themes` became `gruvbox-theme`.** `doom-modeline` did not move: it is
  a standalone MELPA package that wants `nerd-icons` and nothing else from that
  world. See "Deliberate differences — appearance".
- **`dev-disk` lost its Doom row.** `~/.local/share/nix-doom` is not removed by
  `hms`; deleting it is step 2 of `../RETIRING-DOOM.md`.

## Deliberate differences from Doom — appearance

**`gruvbox-theme`, `gruvbox-dark-medium`.** doom-themes exists to ship ~60
themes plus Doom-specific extras and the only one ever loaded here was
`doom-gruvbox`. The palettes are near-identical — bg0 `#282828`, bg1 `#3c3836`,
fg1 `#ebdbb2`, yellow `#fabd2f`, green `#b8bb26`, blue `#83a598`, purple
`#d3869b`, aqua `#8ec07c` all match, and only red differs by one digit
(`#fb4934` upstream, `#fb4933` in doom-gruvbox). **Medium**, not hard or soft,
because bg0 `#282828` is medium's; hard is `#1d2021` and soft `#32302f`.

**What is genuinely lost** is doom-themes' extra face definitions for magit,
org and a few other packages. Those faces fall back to their own package
defaults against the same background, so the cost is polish rather than
legibility. That is the accepted half of the trade and it is written here so
nobody re-adds a 60-theme package to get eight faces back without deciding to.

**The italics are the part that could have been lost silently.** Doom's
`custom-set-faces!` hooked `doom-customize-theme-hook`, which is the only
reason the italic comment/keyword/string/doc faces survived `load-theme`
running afterwards; the vanilla equivalent is Emacs 29+
`enable-theme-functions`, and a theme swap is exactly when a hook keyed on
theme loading gets dropped. Section (h) of the gate asserts all four faces, so
the next theme change cannot drop them quietly. It also asserts that
`doom-themes` is **not on `load-path`** — out of the closure, not merely
unloaded.

## The gate

```sh
bash modules/emacs/vanilla/verify.sh
```

Lives in the repo as of phase 3b. It used to live in `/tmp`, one `clear` away
from being lost, and it is the only thing that catches this config's
characteristic failure: `package-enable-at-startup` is nil, so a key can be
bound, show a name in the which-key popup, and be **void** when pressed.

Five stages, in increasing cost:

0. **preflight** — nothing under `modules/emacs/vanilla` is untracked. Flakes
   only see git-tracked files, so a new `lisp/*.el` that has not been
   `git add`ed is simply absent from the store and fails as "Cannot open load
   file", which reads like a broken `require` rather than a missing `git add`
1. **lint** — alejandra, statix, deadnix and shellcheck, each by **exit code**.
   A linter that cannot be resolved is a failure, never a skip
2. **build** — the activation package
3. **a real daemon**, started from the **store** config directory, never from
   `~/.config/emacs`. Not `emacs --batch`: batch does not load `init.el`
4. **in-daemon assertions** — `verify.el`

What `verify.el` asserts, section by section:

- **(a)** every command reachable by walking the **actual** leader keymap is
  `fboundp`, and every non-borrowed leader key renders as a name
- **(b)** one real sample file per language lands in the expected major mode
  with the expected parser
- **(d)** eglot's contacts and hooks are as intended
- **(e)** claude: `claude-diff` is *loaded* rather than merely autoloadable and
  its commands are real definitions; the four `claude-code` commands are stubs
  that resolve to real definitions when the file loads; the fallback advice
  makes `(claude-code-normalize-project-root nil)` return a string; and the
  window rule is **measured** — a `*claude:*` buffer is displayed, its
  `window-side` parameter read, and `delete-other-windows` actually attempted
  from it. Then the caller's guard is tested from a real side window, with a
  **control that asserts the unguarded call does signal first**, so that half
  of the check can fail
- **(f)** lilypond: the mode, `comment-start`, the backend registered and
  `flymake-mode` *off*, the build hook, the failure buffer's display rule — and
  a real `lilypond` run over four files asserting the diagnostics, including
  the warning-with-no-column and the relative-`\include` cases
- **(g)** popups: `window-sides-slots`, `SPC ~` resolving to a command that is
  `fboundp` *and* interactive, and then a real `*Help*` buffer displayed on the
  daemon's real frame — `window-side`, the height against the fraction the
  gate keeps its **own** copy of, the `mode-line-format` window parameter, the
  dedication value, and that `other-window` can still reach it. The `SPC ~`
  round trip is asserted **in both directions**: a one-way test would pass on a
  toggle that had lost `window-state-put` entirely. Then composition — with a
  popup on screen, a `*claude:*` buffer and a ` *lilypond: *` buffer must each
  still get an ordinary window, and `delete-other-windows` from the Claude
  window must still clear the popup
- **(h)** appearance: exactly one enabled theme, `doom-themes` absent from
  `load-path`, `doom-modeline-mode` on, the truecolor `default` face read out
  of the theme's own `theme-settings`, and all four italic faces. It reads
  `theme-settings` rather than `face-attribute` because the daemon's initial
  frame reports `(display-color-cells)` = 0 and answers `"unspecified-bg"` for
  every theme, including none — an assertion against that would have been green
  with no theme loaded at all
- **(i)** org-gcal: the background fetch timer exists and repeats at 1800s,
  **and** `my/org-gcal-fetch-inhibit` is non-nil in this daemon. Runs
  **first**, and cancels the timer afterwards: its initial delay is 90 seconds
  and `verify.sh` allows 120 for readiness alone, so every other section is
  potentially past it
- **(c)** `*Messages*` carries no warnings or errors — run last, so anything
  the other sections provoked has landed

It walks the keymap rather than a hand-written list of commands, because a
hand-written list is how six void commands shipped once already. On its first
run against phase 3b it failed three assertions, one of which was a real bug
(`nix-ts-mode` resolving to no eglot server) and two of which were bugs in the
gate itself — both of the "confident, precise, wrong number" kind, which is why
each now carries a comment about the trap.

On phase 4 it did it again, twice in a row: it caught a bug in the *test*
(reading a flymake diagnostic's position after its buffer was killed, which
surfaces as "Selecting deleted buffer" and reads like a broken backend), and
then a real bug in `claude-diff--select-main-window` — whose first version
guarded with `(when (window-live-p main) ...)` and did nothing at all, because
`window-main-window` returns an **internal** window whenever the main area
holds more than one window. The design note said the guard was correct; the
daemon said `#<window 3> live=nil`.

The popup layer made it three for three, and again one real bug and one gate
bug. The real one: `window-toggle-side-windows` round-trips the frame through
`window-state-get`/`window-state-put`, and those copy a window parameter only
if it is named in `window-persistent-parameters` — whose default names
`window-side` and `window-slot` and **not** `mode-line-format`. So `SPC ~`
twice brought the popup back *with* a mode line, permanently, with nothing
logged and nothing raised. One line
(`(add-to-list 'window-persistent-parameters '(mode-line-format . writable))`)
fixes it, and it exists only because the toggle was tested in both directions.
The gate bug was the `other-window` reachability check stepping **once** and
assuming a two-window frame; it now walks the whole cycle.

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
