# Retiring Doom — what is left for a human

Doom is out of this repo. `modules/emacs/doom.d/` is deleted, the
`nix-doom-emacs-unstraightened` flake input and its five lock nodes are gone,
`my.emacs` is a single-package option again, and `modules/emacs/vanilla/` is
the only Emacs.

Nothing below happens on `hms`. Each item is either **destructive** or lives
**outside the flake**, which is why it is written down here instead of being
done in a commit. Work through it in order — item 2 makes item 3 irreversible.

---

## 1. Switch, then check the daemon actually turned over

```sh
hms
systemctl --user status emacs
emacsclient -e '(emacs-version)'          # default socket, no -s
```

Two things changed about that unit and both matter on the first switch:

- It now starts with `--init-directory=~/.config/emacs`. If it does not, the
  daemon is running against `~/.emacs.d` and will look like a config that
  silently reverted.
- `X-RestartIfChanged` is **false**, so `hms` will *not* restart it. That is
  deliberate — it is the daemon holding your buffers now. The first switch
  after this change therefore needs an explicit restart to pick the new Emacs
  up, and that restart kills whatever is in the old daemon:

```sh
# save your buffers first
systemctl --user restart emacs
```

`emd` and `emdt` no longer exist. Neither does the `emacs-doom` unit; a
leftover one from a previous generation is disabled by:

```sh
systemctl --user disable --now emacs-doom 2>/dev/null || true
```

## 2. Reclaim the Doom store and state

`hms` does not remove either of these.

```sh
du -sh ~/.local/share/nix-doom          # Doom's doomLocalDir
rm -rf ~/.local/share/nix-doom

# Only if it exists: the pre-Nix doomemacs checkout, moved aside by
# `hms -b backup` at some point and never cleaned up.
du -sh ~/.config/emacs.backup ~/.emacs.d 2>/dev/null
```

The Doom closure itself leaves the store on the next `ncgd` + `nsc` once no
generation references it. `dev-disk` no longer prints a Doom row, so this is
the only reminder that the directory is there.

## 3. Retire the passphrase-less GPG key

**Key: `050C399D3A6B013DD2C93F899BC379782DFE1930`** (uid `org-gcal-token`).

### What it was for

It encrypted Doom's org-gcal OAuth token store
(`~/.config/org-gcal/oauth2-auto.plist`, a GPG plstore) with no passphrase, so
a headless daemon could decrypt a refresh token without a pinentry prompt it
had no frame to draw. It was imported into the keyring on every activation and
marked ultimately trusted so gpg would encrypt to it non-interactively.

Nothing uses it now. The vanilla config stores the same refresh token in
`~/.local/state/emacs/oauth2-auto.eld` as a plain `0600` file — see the
commentary in `modules/emacs/vanilla/config/lisp/my-secrets.el` for why that is
not the downgrade it looks like. The short version: the plstore was encrypted
to a key whose private half sat unprotected at `0600` on the same disk, so the
encryption was never adding anything over the file mode, and it cost a
certify-capable always-unlocked key in the keyring.

### The code change is already done

`modules/sops.nix` no longer decrypts `org_gcal/gpg_private_key`, no longer
imports it into `~/.gnupg`, and no longer sets its ownertrust. After an `hms`,
`~/.config/sops-nix/secrets/org_gcal_gpg_private_key` is removed.

### What you have to do by hand

**Before anything else**, confirm you do not still need to read Doom's plstore.
If `~/.local/state/emacs/oauth2-auto.eld` exists and org-gcal fetches without
sending you to a browser, you do not. If it is missing and you would rather not
redo the OAuth flow, run `M-x my/oauth2-import-from-plstore` **first** — it
reads the plstore, and once the key is gone that command cannot work again.

```sh
# a) prove nothing else is encrypted to it
gpg --list-keys 050C399D3A6B013DD2C93F899BC379782DFE1930

# b) the last consumer, once you no longer need it
rm -f ~/.config/org-gcal/oauth2-auto.plist ~/.config/org-gcal/token.plstore
rmdir ~/.config/org-gcal 2>/dev/null || true

# c) delete the key -- SECRET FIRST, gpg refuses the public half otherwise
gpg --batch --yes --delete-secret-keys 050C399D3A6B013DD2C93F899BC379782DFE1930
gpg --batch --yes --delete-keys        050C399D3A6B013DD2C93F899BC379782DFE1930

# d) and the decrypted copy, if an hms has not already removed it
rm -f ~/.config/sops-nix/secrets/org_gcal_gpg_private_key
```

Repeat (c) and (d) on **every** machine that has ever run `hms` — the key was
imported by the activation script, so it is in each keyring independently.

### Then drop it from the encrypted secrets file

`secrets/secrets.yaml` is **not** edited by hand: the whole file carries a MAC
and a text edit corrupts it. Use sops, which re-MACs:

```sh
cd ~/.config/home-manager
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops unset secrets/secrets.yaml '["org_gcal"]["gpg_private_key"]'
git diff --stat secrets/secrets.yaml     # one file, and it still decrypts
sops -d secrets/secrets.yaml | head -20  # prove it before committing
```

`org_gcal/client_id` and `org_gcal/client_secret` **stay** — they are the
Google OAuth application credentials and org-gcal still reads them out of
`~/.config/sops-nix/secrets/`.

### Revocation

The key never left this machine and was never published to a keyserver, so
there is nothing to revoke *to*. If a revocation certificate was generated at
creation time it is at `~/.gnupg/openpgp-revocs.d/050C…1930.rev`; deleting the
secret key in (c) makes generating one afterwards impossible, so if you want
one, take it before step (c).

## 4. Windows side

Not managed by this flake and will otherwise drift: nothing in
`C:\Users\brona` references Doom today, but if any Windows shortcut, scheduled
task or `wsl.exe` wrapper invokes `emd`, `emacsclient -s doom`, or
`~/.local/share/nix-doom`, it has to be repointed at `em` / the default socket
by hand.

---

## What is deliberately still here

- **`my/oauth2-import-from-plstore`** in
  `modules/emacs/vanilla/config/lisp/my-secrets.el`. It is the only recovery
  path from a lost `.eld` back to Doom's plstore, and deleting it in the same
  change that removes the plstore's key would remove the recovery path and the
  thing it recovers from at once. Once step 3 is done it is genuinely dead and
  can go.
- **`org_gcal/client_id` and `org_gcal/client_secret`** in sops. Still used.
