;;; my-secrets.el --- credential plumbing -*- lexical-binding: t; -*-

;;; Commentary:

;; Two things, both about keeping exactly one secret system rather than two.
;;
;; 1. `my/sops-secret' reads a credential that sops-nix decrypted at `hms'
;;    time.  Durable inputs (OAuth client id/secret) live there and nowhere
;;    else.
;;
;; 2. `my/oauth2-auto-use-plain-store' replaces oauth2-auto's plstore backend
;;    with a plain 0600 file.
;;
;; The second one deserves its reasoning written down, because it looks like a
;; downgrade and is not.
;;
;; oauth2-auto stores the Google refresh token via `plstore-put' with the
;; plist in the SECRET slot, so plstore writes it inside an OpenPGP block.
;; There is no setting that turns that off: `plstore--insert-buffer' calls
;; `epg-encrypt-string' unconditionally whenever a `:secret-' entry exists,
;; and `plstore-encrypt-to' nil only downgrades it to SYMMETRIC encryption --
;; a passphrase, not plaintext.  So "no GPG here" cannot be a variable; it has
;; to be a different backend.  Hence the override rather than a `setq'.
;;
;; What the GPG layer was actually buying: under Doom the store is encrypted
;; to a dedicated key that has NO PASSPHRASE, and whose private half sits at
;; 0600 in ~/.config/sops-nix/secrets/ -- the same disk, the same user, as the
;; file it protects.  Anyone who can read the ciphertext can read the key that
;; opens it.  That is encryption with the key taped to the box; the real
;; protection was already filesystem permissions plus disk encryption.
;;
;; It cannot be fixed by encrypting to the YubiKey key instead, because the
;; whole point is unattended refresh: the background fetch has no human to
;; touch the card.  Unattended decryption and a key that isn't on disk are
;; mutually exclusive, and the choice here is unattended.
;;
;; So this drops the pretence and keeps the protection that was doing the
;; work: 0600, enforced at creation time rather than after the fact.  What
;; goes with it is a private key, a sops secret, a keyring import and a
;; sops-nix decrypt block -- one system instead of two.

;;; Code:

(require 'cl-lib)

;;;; sops-nix

(defcustom my/sops-secrets-directory
  (expand-file-name "~/.config/sops-nix/secrets/")
  "Directory sops-nix decrypts secrets into during home-manager activation."
  :type 'directory
  :group 'my)

(defun my/sops-secret (name)
  "Return the sops-nix secret NAME as a trimmed string, or nil.

Returns nil rather than signalling when the secret is absent, so a config
that references a credential still loads on a machine that has not run
`hms', or before the first decrypt."
  (let ((path (expand-file-name name my/sops-secrets-directory)))
    (when (file-readable-p path)
      (string-trim
       (with-temp-buffer
         (insert-file-contents path)
         (buffer-string))))))

;;;; oauth2-auto: plain-file token store

(defvar my/oauth2-store-file nil
  "File holding oauth2-auto refresh tokens, as a plain alist.

Set by `my/oauth2-auto-use-plain-store'.  This is DURABLE state, not cache:
losing it means redoing the browser authorisation flow.  It therefore belongs
under `no-littering-etc-directory' (~/.local/state) and never under
`no-littering-var-directory' (~/.cache), which is treated as disposable.")

(defun my/oauth2--read-all ()
  "Return the whole token alist, or nil if the store is absent or corrupt."
  (when (and my/oauth2-store-file (file-readable-p my/oauth2-store-file))
    (with-temp-buffer
      (insert-file-contents my/oauth2-store-file)
      (goto-char (point-min))
      ;; A truncated write must not wedge startup: an unreadable store means
      ;; one browser re-auth, whereas a read error here aborts whatever
      ;; org-gcal was in the middle of.
      (condition-case err
          (read (current-buffer))
        (error
         (message "my/oauth2: unreadable token store %s (%s); re-auth needed"
                  my/oauth2-store-file (error-message-string err))
         nil)))))

(defun my/oauth2--write-all (alist)
  "Write ALIST to `my/oauth2-store-file' with mode 0600."
  (let ((dir (file-name-directory my/oauth2-store-file))
        (modes (default-file-modes)))
    (make-directory dir t)
    ;; Bind the process umask around the write instead of chmod-ing after it.
    ;; `set-file-modes' on an existing file leaves a window -- however brief --
    ;; where a live refresh token is world-readable, and this file is rewritten
    ;; on every token refresh, so that window recurs rather than happening once.
    (unwind-protect
        (progn
          (set-default-file-modes #o600)
          (with-temp-file my/oauth2-store-file
            (insert ";;; oauth2-auto tokens -*- lexical-binding: t; no-byte-compile: t; -*-\n"
                    ";;; Written by my/oauth2--write-all.  Do not edit.\n"
                    ";;; Contains live Google refresh tokens.  Mode 0600, deliberately\n"
                    ";;; unencrypted -- see the commentary in my-secrets.el.\n")
            (let ((print-length nil)
                  (print-level nil))
              (pp alist (current-buffer)))))
      (set-default-file-modes modes))
    ;; Belt and braces: an existing file keeps its old modes through
    ;; `write-region', so the umask above only covers creation.
    (set-file-modes my/oauth2-store-file #o600)))

(defun my/oauth2-auto--plstore-read (username provider)
  "Read the token plist for USERNAME and PROVIDER from the plain store.

Drop-in for `oauth2-auto--plstore-read': returns the plist with UNPREFIXED
keys (:access-token, :refresh-token, :expiration), which is what
`plstore-get' hands back after decrypting -- it strips the `:secret-'
prefix -- and what the rest of oauth2-auto expects."
  (let ((id (oauth2-auto--compute-id username provider)))
    (puthash id
             (cdr (assoc id (my/oauth2--read-all)))
             oauth2-auto--plstore-cache)))

(defun my/oauth2-auto--plstore-write (username provider plist)
  "Write PLIST for USERNAME and PROVIDER to the plain store.

Drop-in for `oauth2-auto--plstore-write'.  Re-reads the file rather than
trusting the in-memory cache, so a second Emacs refreshing the same account
does not get its entry dropped on the next write from this one."
  (let* ((id (oauth2-auto--compute-id username provider))
         (all (my/oauth2--read-all))
         (cell (assoc id all)))
    (if cell
        (setcdr cell plist)
      (setq all (cons (cons id plist) all)))
    (my/oauth2--write-all all)
    (puthash id plist oauth2-auto--plstore-cache)
    plist))

(defun my/oauth2-auto-use-plain-store (file)
  "Point oauth2-auto at FILE, a plain 0600 alist, instead of a plstore.

Overrides both halves of oauth2-auto's storage layer.  Overriding only the
write half would leave reads going through plstore and still invoking GPG.

The advice is attached through `with-eval-after-load' rather than directly,
and this function is called at config-load time rather than from some
package's deferred `:config'.  That ordering is deliberate: whether this
Emacs ever invokes GPG is a property of the config, and it must not depend
on WHICH package happens to pull in oauth2-auto first.  If the override were
installed lazily and something loaded oauth2-auto ahead of it, storage would
silently fall back to plstore -- writing an encrypted file, or blocking a
headless daemon on a pinentry prompt that has no frame to appear in."
  (setq my/oauth2-store-file (expand-file-name file))
  (with-eval-after-load 'oauth2-auto
    (advice-add 'oauth2-auto--plstore-read  :override #'my/oauth2-auto--plstore-read)
    (advice-add 'oauth2-auto--plstore-write :override #'my/oauth2-auto--plstore-write)))

;;;; One-time migration off the encrypted store

(defun my/oauth2-import-from-plstore (plstore-file)
  "Copy every entry from PLSTORE-FILE into `my/oauth2-store-file'.

Interactive and one-shot on purpose.  This is the ONLY thing in the vanilla
config that touches GPG, and running it at startup would reintroduce exactly
the unattended-pinentry problem the plain store exists to remove.

Use it once to inherit Doom's authorisation instead of redoing the browser
flow; after that it never runs again.  Doom keeps its own encrypted store --
this reads it, it does not move it -- so both stayed working during
the parallel period.  Google issues independent access tokens from the same
refresh token, so two live caches do not fight."
  (interactive
   (list (read-file-name "Import from plstore: "
                         "~/.config/org-gcal/" nil t "oauth2-auto.plist")))
  (require 'plstore)
  (unless my/oauth2-store-file
    (user-error "my/oauth2-store-file is unset; call my/oauth2-auto-use-plain-store first"))
  (let ((store (plstore-open (expand-file-name plstore-file)))
        (all (my/oauth2--read-all))
        (n 0))
    (unwind-protect
        (dolist (entry (plstore-find store nil))
          (let* ((id (car entry))
                 ;; plstore-find returns entries with :secret- keys still
                 ;; prefixed; plstore-get is what forces the decrypt and hands
                 ;; back the plain plist.
                 (plist (cdr (plstore-get store id)))
                 (cell (assoc id all)))
            (when (plist-get plist :refresh-token)
              (if cell (setcdr cell plist) (setq all (cons (cons id plist) all)))
              (setq n (1+ n)))))
      (plstore-close store))
    (my/oauth2--write-all all)
    (clrhash oauth2-auto--plstore-cache)
    (message "my/oauth2: imported %d token%s into %s"
             n (if (= n 1) "" "s") my/oauth2-store-file)))

(provide 'my-secrets)
;;; my-secrets.el ends here
