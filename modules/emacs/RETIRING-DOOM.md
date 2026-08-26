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

## 3. The `org-gcal-token` GPG key — nothing to do

**This is not a task.** It is here so that finding a stray key in your keyring
later does not read as a mystery.

`050C399D3A6B013DD2C93F899BC379782DFE1930`, uid `org-gcal-token`, is a
passphrase-less key generated for one purpose: encrypting Doom's org-gcal
plstore so a headless daemon could read a refresh token without a pinentry
prompt it had no frame to draw. **It is not a signing key and has nothing to do
with commit signing** — that is `ECA2632B08E80FC6`, on the YubiKey.

The code change already shipped (`9fcf26f`): `modules/sops.nix` no longer
decrypts `org_gcal/gpg_private_key`, no longer imports it, and no longer sets
its ownertrust. Nothing reads the key. It sits inert in `~/.gnupg` and costs
nothing to leave there indefinitely.

If you ever do want it gone, the only ordering that matters is that
`M-x my/oauth2-import-from-plstore` stops working once the secret key is
deleted — so confirm `~/.local/state/emacs/oauth2-auto.eld` exists and org-gcal
fetches without a browser round-trip first. `secrets/secrets.yaml` would then
need `sops unset '["org_gcal"]["gpg_private_key"]'` rather than a text edit,
because the file carries a MAC. `org_gcal/client_id` and
`org_gcal/client_secret` stay either way — those are the Google OAuth
application credentials and org-gcal still reads them.


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
  thing it recovers from at once. It stays as long as the key does, which is
  indefinitely — see section 3.
- **`org_gcal/client_id` and `org_gcal/client_secret`** in sops. Still used.
