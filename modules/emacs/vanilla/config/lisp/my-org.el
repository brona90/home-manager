;;; my-org.el --- Org: agenda, capture, refile, Google Calendar -*- lexical-binding: t; -*-

;;; Commentary:

;; Phase 2 of the Doom port.  A faithful transcription of the `after! org' and
;; `use-package! org-gcal' blocks in modules/emacs/doom.d/config.el, with the
;; Doom macros unwound:
;;
;;   (after! org ...)     ->  (with-eval-after-load 'org ...), which is all
;;                            `after!' expands to for a single feature
;;   (use-package! X ...) ->  (use-package X ...); `use-package' is built in
;;                            since Emacs 29 and needs no :ensure here because
;;                            every package comes from the Nix closure
;;   (map! :leader ...)   ->  the `my/leader' general definer from init.el
;;
;; `:lang org' carries NO flags in doom.d/init.el, so there is no Doom glue to
;; reproduce beyond the module's package set -- of which only `evil-org' is
;; load-bearing for muscle memory.
;;
;; Two deliberate differences from Doom, both about running as a SECOND Emacs
;; beside the daily driver.  Both are listed in GRADUATION.md and both revert
;; when this becomes the only Emacs:
;;
;;   1. No background fetch timer.  Doom re-fetches every 30 minutes.  Two
;;      daemons on that timer would write ~/org/gcal*.org underneath each
;;      other, and the one with the buffer open would hit
;;      "file changed on disk" -- turning a trial config into a data-loss
;;      question about real calendar entries.  Fetch here is manual.
;;   2. The OAuth token store is a plain 0600 file, not a GPG-encrypted
;;      plstore.  See the commentary in my-secrets.el for why that is not the
;;      downgrade it looks like.

;;; Code:

(require 'my-secrets)
;; For `no-littering-etc-directory' below.  init.el already loads no-littering
;; first, but relying on that would make this file's correctness depend on load
;; ORDER in another file -- and the thing it decides is where a live credential
;; gets written.
(require 'no-littering)

;;;; Org core

;; Must be set before org loads, hence outside the `with-eval-after-load'.
(setq org-directory "~/org/")

;; Autoload stubs for the org commands the leader map names.
;;
;; `org-agenda' and `org-capture' come free: they live in org-agenda.el and
;; org-capture.el, whose autoload cookies are picked up by Emacs's own
;; loaddefs. `org-store-link' and `org-refile' live in org.el itself, whose
;; autoloads sit in org-loaddefs.el and are loaded by package.el ACTIVATION --
;; which early-init.el disables. Without this form both resolve to a symbol and
;; then fail with void-function on the keypress.
;;
;; Verified rather than assumed: in a freshly started daemon before this form,
;; (fboundp 'org-store-link) and (fboundp 'org-refile) were both nil while
;; (key-binding (kbd "SPC m r")) happily returned `org-refile'. Checking the
;; binding proves nothing about the command.
(use-package org
  :commands (org-store-link org-refile))

(with-eval-after-load 'org
  ;; Which files the agenda scans.  Deliberately a curated list rather than
  ;; the whole ~/org dir, so old scratch/learning files don't pollute the
  ;; agenda.  Add files here as they are created.
  (setq org-agenda-files
        (mapcar (lambda (f) (expand-file-name f org-directory))
                '("inbox.org" "todo.org" "projects.org"
                  "gcal.org" "gcal-louis.org" "gcal-cog.org")))

  ;; A simple, legible task lifecycle.  The letters in (..) are fast-select
  ;; keys; @ = prompt for a note, ! = timestamp the state change.
  (setq org-todo-keywords
        '((sequence "TODO(t)" "NEXT(n)" "WAIT(w@/!)" "|" "DONE(d)" "CANCELLED(c@)")))
  (setq org-log-done 'time              ; stamp CLOSED: when a task is finished
        org-log-into-drawer t)          ; tuck state-change logs into a :LOGBOOK:

  ;; Refile: move a captured item into todo.org / projects.org.
  (setq org-refile-targets '((org-agenda-files :maxlevel . 3))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil)

  ;; Capture templates.  Each drops a new entry into the right file so you
  ;; never lose a thought.
  (setq org-capture-templates
        '(("t" "Todo -> inbox" entry
           (file+headline "inbox.org" "Inbox")
           "* TODO %?\n%U\n%i" :empty-lines 1)
          ("n" "Note -> inbox" entry
           (file+headline "inbox.org" "Inbox")
           "* %?\n%U\n%i" :empty-lines 1)
          ("e" "Event -> personal calendar (syncs to Google)" entry
           (file+headline "gcal.org" "brona90@gmail.com")
           "* %?\n%^T\n" :empty-lines 1)))

  ;; Daily dashboard: `SPC o a' then `d' = one screen with the next 3 days of
  ;; calendar/scheduled/deadlines, then NEXT actions, then what you're
  ;; waiting on.
  (setq org-agenda-custom-commands
        '(("d" "Daily dashboard"
           ((agenda "" ((org-agenda-span 3)
                        (org-agenda-start-day "0d") ; pin to today (global default is "-3d")
                        (org-deadline-warning-days 14)
                        (org-agenda-overriding-header "Next 3 days")))
            (todo "NEXT" ((org-agenda-overriding-header "Next actions")))
            (todo "WAIT" ((org-agenda-overriding-header "Waiting on"))))))))

;; Doom's `:lang org' loads this; without it `TAB', `gj'/`gk', `<'/`>' and the
;; org text objects all behave like plain evil and folding stops working the
;; way ten years of muscle memory expects.
(use-package evil-org
  :hook (org-mode . evil-org-mode)
  :config
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

;;;; org-gcal

;; FIRST-TIME SETUP is unchanged from Doom and already done -- the Google
;; Cloud OAuth client exists and its credentials are in sops:
;;
;;   sops set secrets/secrets.yaml '["org_gcal"]["client_id"]'     '"...id..."'
;;   sops set secrets/secrets.yaml '["org_gcal"]["client_secret"]' '"...secret..."'
;;
;; sops-nix (modules/sops.nix) decrypts them on `hms' to
;; ~/.config/sops-nix/secrets/org_gcal_client_{id,secret}.
;;
;; To authorise THIS Emacs without redoing the browser flow, run
;; `M-x my/oauth2-import-from-plstore' once and accept the default path.  That
;; is the only GPG call in this config, and it never runs on its own.

;; NO `:after org'. It reads like the right dependency -- org-gcal does need
;; org -- but `:after' defers the AUTOLOAD STUBS as well as the :config, so
;; until something else loaded org, all three commands below were unbound and
;; `SPC m G s' failed with void-function instead of syncing. org-gcal has its
;; own (require 'org), so ordering was never actually at risk.
(use-package org-gcal
  :commands (org-gcal-sync org-gcal-fetch org-gcal-post-at-point)
  :config
  ;; Credentials come from sops-nix, never from this file.
  (when-let ((id (my/sops-secret "org_gcal_client_id")))
    (setq org-gcal-client-id id))
  (when-let ((secret (my/sops-secret "org_gcal_client_secret")))
    (setq org-gcal-client-secret secret))

  ;; org-gcal registers its oauth2-auto provider at LOAD time, but the creds
  ;; above are set after load -- so re-register now or the first sync fails
  ;; with "oauth2-auto: Unknown provider: org-gcal".
  (when (and org-gcal-client-id org-gcal-client-secret)
    (org-gcal-reload-client-id-secret))

  ;; NOT set: `org-gcal-token-file'.  Doom points it at
  ;; ~/.config/org-gcal/token.plstore, which has never existed on this
  ;; machine -- current org-gcal delegates storage entirely to oauth2-auto.
  ;; Carrying the setting across would carry a dead line.
  ;;
  ;; The token store is NOT configured here either; see below for why it has
  ;; to happen outside this deferred block.

  ;; Keep the org files small.  org-gcal expands recurring events into one
  ;; entry per occurrence, so a wide window means thousands of headings.
  (setq org-gcal-up-days 14
        org-gcal-down-days 45
        org-gcal-auto-archive t)

  ;; NOTE: gcal-cog.org maps to the "COG" calendar -- a Google Apps
  ;; Script-populated mirror of the Cognizant calendar.  Treat it READ-ONLY:
  ;; pull with `org-gcal-fetch' and don't edit its headings, because edits
  ;; would hit the mirror, not the source.
  (setq org-gcal-fetch-file-alist
        '(("brona90@gmail.com" . "~/org/gcal.org")
          ("oe0etoam5k8o95sqd1qnisio44@group.calendar.google.com" . "~/org/gcal-louis.org")
          ("140a3ad65e2a46fe9a58a74035d2e489482e704c008622767304b36ca33c4b47@group.calendar.google.com" . "~/org/gcal-cog.org")))

  ;; org-gcal populates buffers but never saves them -- which is what made the
  ;; COG calendar look like it wasn't syncing at all.
  (defun my/org-gcal-save-buffers (&optional result)
    "Save modified org-gcal-managed buffers.
Covers the live gcal*.org files and their _archive siblings.  RESULT is
returned unchanged, so this can sit in a deferred chain without altering
the value handed to whatever runs next."
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (and buffer-file-name
                   (buffer-modified-p)
                   (string-match-p "/org/gcal.*\\.org\\(_archive\\)?\\'" buffer-file-name))
          (save-buffer))))
    result)

  (defun my/org-gcal--save-after (orig &rest args)
    "Around-advice: save org-gcal buffers once the (async) ORIG completes.
ORIG is called with ARGS.  org-gcal returns a deferred object when it went
async and a plain value when it did not, so both paths are handled."
    (let ((d (apply orig args)))
      (if (and (fboundp 'deferred-p) (deferred-p d))
          (deferred:nextc d #'my/org-gcal-save-buffers)
        (my/org-gcal-save-buffers)
        d)))

  (advice-add 'org-gcal-sync  :around #'my/org-gcal--save-after)
  (advice-add 'org-gcal-fetch :around #'my/org-gcal--save-after))

;; Deliberately OUTSIDE the `use-package' block above, and therefore run when
;; this file loads rather than when org-gcal does.
;;
;; Everything in that `:config' is deferred until the first `org-gcal-sync' --
;; faithful to Doom, and harmless for settings.  It is not harmless for this
;; one, because "this Emacs never invokes GPG" is a property of the config,
;; not of org-gcal's load order.  org-gcal is not the only possible consumer
;; of oauth2-auto, and anything that reached it first would get the plstore
;; backend: an encrypted write, or a headless daemon blocked on a pinentry
;; prompt with no frame to draw it in.
;;
;; `.eld' rather than `.plist': the format is a plain alist, and reusing the
;; name of the file it replaces would invite someone to open it with plstore
;; and be told it is corrupt.  A separate path from Doom's, so both flavours
;; keep working through the parallel period.
(my/oauth2-auto-use-plain-store
 (expand-file-name "oauth2-auto.eld" no-littering-etc-directory))

;; NO background fetch timer here.  Doom runs `org-gcal-fetch' every 30
;; minutes; see the commentary at the top for why a second daemon must not.
;; Restore it from doom.d/config.el when this config graduates and Doom stops.

;;;; Bindings

;; `my/local-leader' is `SPC m' in the general OVERRIDE map, which is global
;; rather than mode-local as Doom's localleader is.  That is a known deviation
;; and the reason is structural: the override map is an evil INTERCEPT map, so
;; once `SPC' resolves there, `org-mode-map' is never consulted for the rest
;; of the sequence.  Making `SPC m' genuinely mode-local needs a dispatcher
;; keymap, which belongs with the rest of the bindings work rather than here.
;;
;; The practical cost is small: sync and fetch are whole-calendar operations
;; that make sense from any buffer, and `org-gcal-post-at-point' errors
;; clearly outside an org buffer.

(with-eval-after-load 'general
  (my/leader
    "X"  #'org-capture
    "o"  '(:ignore t :which-key "open")
    "oa" #'org-agenda
    "ol" #'org-store-link)

  (my/local-leader
    "r"  #'org-refile
    "G"  '(:ignore t :which-key "gcal")
    "Gs" #'org-gcal-sync
    "Gf" #'org-gcal-fetch
    "Gp" #'org-gcal-post-at-point))

(provide 'my-org)
;;; my-org.el ends here
