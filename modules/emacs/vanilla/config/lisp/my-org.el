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
;; One deliberate difference from Doom remains:
;;
;;   The OAuth token store is a plain 0600 file, not a GPG-encrypted plstore.
;;   See the commentary in my-secrets.el for why that is not the downgrade it
;;   looks like.  This one is permanent.
;;
;; The other -- no background fetch timer -- was a property of running as a
;; SECOND Emacs beside Doom, and it expired with Doom.  Two daemons on a
;; 30-minute timer would have written ~/org/gcal*.org underneath each other
;; and the one holding the buffer would have hit "file changed on disk", which
;; is a data-loss question about real calendar entries rather than a
;; preference.  With one daemon there is one writer, and the timer is restored
;; at the bottom of this file.

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
;; loaddefs. Nothing else does, because org's OWN autoload file is loaded by
;; package.el ACTIVATION -- which early-init.el disables. Without a stub a
;; command resolves to a symbol and then fails with void-function on the
;; keypress.
;;
;; Verified rather than assumed: in a freshly started daemon before this form,
;; (fboundp 'org-store-link) and (fboundp 'org-refile) were both nil while
;; (key-binding (kbd "SPC m r")) happily returned `org-refile'. Checking the
;; binding proves nothing about the command.
;;
;; TWO forms, because org is spread over ~40 files:
;;
;;   1. `org-loaddefs.el' is org's own generated autoload file -- 274 stubs,
;;      each naming the file that ACTUALLY defines the command (org-clock-in ->
;;      "org-clock", org-export-dispatch -> "ox", org-refile -> "org-refile").
;;      Requiring it beats enumerating those in `:commands', which would emit
;;      (autoload SYM "org") and fail at keypress time with "Autoloading file
;;      ... failed to define function". It costs nothing at startup: the file
;;      is autoload forms only and pulls in no org code.
;;
;;   2. A `:commands' list for the commands that carry no cookie at all and DO
;;      live in org.el -- which is most of the localleader. Checked file by
;;      file against org 9.8.9 rather than assumed.
(require 'org-loaddefs)

(use-package org
  :commands (org-clone-subtree-with-time-shift
             org-cut-subtree
             org-deadline
             org-demote-subtree
             org-edit-special
             org-move-subtree-down
             org-move-subtree-up
             org-narrow-to-subtree
             org-priority
             org-priority-down
             org-priority-up
             org-promote-subtree
             org-refile
             org-schedule
             org-set-effort
             org-set-property
             org-set-tags-command
             org-sort
             org-sparse-tree
             org-store-link
             org-switchb
             org-timestamp
             org-timestamp-inactive
             org-todo
             org-toggle-heading
             org-tree-to-indirect-buffer
             org-update-statistics-cookies))

;; org-list.el and org-agenda.el residents. Separate forms for the same reason
;; the consult sub-packages in init.el get separate forms: `:commands' names
;; the enclosing package's FILE, and "org" is the wrong file for these.
(use-package org-list
  :commands (org-toggle-checkbox org-toggle-item))

(use-package org-agenda
  :commands (org-search-view org-tags-view org-todo-list))

(use-package org-capture
  :commands (org-capture-goto-target))

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
;; and be told it is corrupt.  It was also a separate path from Doom's so both
;; could keep working through the parallel period; Doom is retired and this is
;; simply the store now.
(my/oauth2-auto-use-plain-store
 (expand-file-name "oauth2-auto.eld" no-littering-etc-directory))

;;;; Background fetch
;;
;; ~90s after the daemon starts, then every 30 minutes.  Ported verbatim in
;; behaviour from the Doom config this replaced; it was omitted for the whole
;; parallel period because two daemons cannot both own ~/org/gcal*.org, and
;; restored here now that there is one Emacs again.
;;
;; The `my/org-gcal--save-after' advice installed above is what makes this
;; worth having: org-gcal populates buffers and never saves them, so without
;; the advice a background fetch would leave the agenda current only in memory
;; and the files stale on disk.
;;
;; `require' rather than a bare call: org-gcal is deferred (`:commands'
;; above), so on a daemon that has not yet run a gcal command the package is
;; not loaded and `org-gcal-client-id' is not even bound.  Loading it is what
;; runs the `:config' block that reads the sops credentials -- and the
;; `bound-and-true-p' guard after it is what stops an unconfigured machine
;; (no sops age key, so no client id) from firing a fetch every 30 minutes
;; that can only fail.  NOERROR on the `require' covers the same case one
;; level up.
;; THE GATE MUST NOT FETCH.  modules/emacs/vanilla/verify.sh starts a real
;; daemon from the store config -- that is the whole point of it -- and a
;; daemon with this timer running would, 90 seconds in, pull the real Google
;; Calendar and write ~/org/gcal*.org while the user's actual daemon has those
;; files open.  That is precisely the two-writer data-loss case the timer was
;; withheld for during the parallel period, reintroduced by the test harness.
;;
;; Keyed on the variable verify.sh already exports to tell the daemon where to
;; write its report, so there is nothing extra for the gate to remember to set.
;; verify.el asserts this is non-nil in the gate daemon AND that the timer is
;; installed anyway, so neither half can rot silently: drop the export and the
;; gate goes red rather than quietly fetching.
(defvar my/org-gcal-fetch-inhibit (and (getenv "EMACS_VANILLA_VERIFY_OUT") t)
  "Non-nil to suppress the background Google Calendar fetch.
Set from the environment at load time so a gate daemon never races the real
one for ~/org/gcal*.org.  Also settable by hand to pause the fetch without
cancelling `my/org-gcal-fetch-timer'.")

(defun my/org-gcal-fetch-safe ()
  "Background-fetch Google Calendar if org-gcal is configured.
Does nothing when `my/org-gcal-fetch-inhibit' is non-nil, when org-gcal
cannot be loaded, or when it has no client id -- so an unconfigured machine
gets silence rather than a failure every 30 minutes."
  (when (and (not my/org-gcal-fetch-inhibit)
             (require 'org-gcal nil t)
             (bound-and-true-p org-gcal-client-id))
    (org-gcal-fetch)))

(defvar my/org-gcal-fetch-timer nil
  "Repeating timer for the background Google Calendar fetch.")

;; Cancel-then-set, so re-evaluating this file (M-x eval-buffer while editing
;; it, or a second `load') replaces the timer instead of adding a second one.
;; Two timers would double the API traffic and race each other into the same
;; files -- the exact failure the parallel period was avoiding, reintroduced
;; inside a single daemon.
(when (timerp my/org-gcal-fetch-timer)
  (cancel-timer my/org-gcal-fetch-timer))
(setq my/org-gcal-fetch-timer
      (run-at-time 90 (* 30 60) #'my/org-gcal-fetch-safe))

;;;; Bindings
;;
;; MOVED to lisp/my-bindings.el, which owns the whole leader map. This file
;; still owns the org SETUP -- and, above, the autoload stubs without which
;; those bindings would be names of commands that do not exist.
;;
;; `SPC m G s/f/p' are unchanged. What did move within the map: `SPC o l' is
;; now `SPC n l' and `SPC o a' is now a sub-prefix with `SPC o a a' (plus
;; `SPC o A' and `SPC n a'), both of which are Doom's actual layout.
;;
;; `my/local-leader' is `SPC m' in the general OVERRIDE map, which is global
;; rather than mode-local as Doom's localleader is.  That is a known deviation
;; and the reason is structural: the override map is an evil INTERCEPT map, so
;; once `SPC' resolves there, `org-mode-map' is never consulted for the rest
;; of the sequence.  Making `SPC m' genuinely mode-local needs a dispatcher
;; keymap, which is still not done.
;;
;; The practical cost is small: sync and fetch are whole-calendar operations
;; that make sense from any buffer, and the org commands error clearly outside
;; an org buffer.

(provide 'my-org)
;;; my-org.el ends here
