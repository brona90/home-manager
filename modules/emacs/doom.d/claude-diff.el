;;; claude-diff.el --- 2-way diff review for Claude Code edits -*- lexical-binding: t; -*-
;;
;; Shows before/after diff when Claude Code proposes an edit.
;; Triggered by a PermissionRequest hook that passes tool input JSON.
;; Dismissed automatically by a PostToolUse hook after approval/denial.
;;
;; Keybindings (SPC l prefix, work from the vterm):
;;   n / p  — next / previous change
;;   j / k  — scroll diff up / down
;;   a      — approve (dismiss diff)
;;   x      — deny (revert to HEAD, dismiss diff)
;;   D      — dismiss diff

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)

;; ── Faces ────────────────────────────────────────────────────────────

(defface claude-diff-added
  '((t :background "#1a4a1a" :extend t))
  "Face for added lines in claude diff view."
  :group 'claude-diff)

(defface claude-diff-removed
  '((t :background "#4a1a1a" :extend t))
  "Face for removed lines in claude diff view."
  :group 'claude-diff)

;; ── State ────────────────────────────────────────────────────────────

(defvar claude-diff--current-file nil
  "The file path currently being diffed.")

(defvar claude-diff--scroll-timer nil
  "Timer for deferred scroll-to-first-change.")

(defvar claude-diff--saved-wconf nil
  "Window configuration saved before showing the diff view.")

(defvar claude-diff--auto-dismiss-timer nil
  "Timer that auto-dismisses the diff if PostToolUse never fires (e.g. user denied).")

;; ── Diff highlighting ────────────────────────────────────────────────

(defun claude-diff--highlight (before-buf after-buf)
  "Parse unified diff between BEFORE-BUF and AFTER-BUF, add overlays."
  (let ((before-file (make-temp-file "claude-before"))
        (after-file (make-temp-file "claude-after")))
    (unwind-protect
        (progn
          (with-current-buffer before-buf
            (write-region (point-min) (point-max) before-file nil 'silent))
          (with-current-buffer after-buf
            (write-region (point-min) (point-max) after-file nil 'silent))
          (with-temp-buffer
            (call-process "diff" nil t nil "-u" before-file after-file)
            (goto-char (point-min))
            (while (re-search-forward
                    "^@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@"
                    nil t)
              (let* ((old-start (string-to-number (match-string 1)))
                     (new-start (string-to-number (match-string 3)))
                     (old-line old-start)
                     (new-line new-start))
                (forward-line 1)
                (while (and (not (eobp))
                            (not (looking-at "^@@\\|^diff ")))
                  (cond
                   ((looking-at "^-")
                    (claude-diff--overlay-line before-buf old-line 'claude-diff-removed)
                    (cl-incf old-line))
                   ((looking-at "^\\+")
                    (claude-diff--overlay-line after-buf new-line 'claude-diff-added)
                    (cl-incf new-line))
                   (t
                    (cl-incf old-line)
                    (cl-incf new-line)))
                  (forward-line 1))))))
      (delete-file before-file)
      (delete-file after-file))))

(defun claude-diff--overlay-line (buf line-num face)
  "Add an overlay with FACE to LINE-NUM in BUF."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (when (zerop (forward-line (1- line-num)))
        (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
          (overlay-put ov 'face face)
          (overlay-put ov 'claude-diff t))))))

;; ── Window management ────────────────────────────────────────────────

(defun claude-diff--after-win ()
  "Return the *After:* diff window, or nil."
  (seq-find (lambda (w)
              (string-prefix-p "*After:" (buffer-name (window-buffer w))))
            (window-list)))

(defun claude-diff--before-win ()
  "Return the *Before:* diff window, or nil."
  (seq-find (lambda (w)
              (string-prefix-p "*Before:" (buffer-name (window-buffer w))))
            (window-list)))

(defvar claude-diff--syncing nil
  "Guard to prevent recursive scroll sync.")

(defun claude-diff--sync-windows (target-start)
  "Set both diff windows to show from TARGET-START."
  (when-let ((aw (claude-diff--after-win)))
    (set-window-start aw target-start))
  (when-let ((bw (claude-diff--before-win)))
    (set-window-start bw target-start)))

(defun claude-diff--on-scroll (win start)
  "Sync the partner diff window when WIN scrolls to START."
  (unless claude-diff--syncing
    (let ((claude-diff--syncing t)
          (buf-name (buffer-name (window-buffer win))))
      (cond
       ((string-prefix-p "*Before:" buf-name)
        (when-let ((aw (claude-diff--after-win)))
          (set-window-start aw start)))
       ((string-prefix-p "*After:" buf-name)
        (when-let ((bw (claude-diff--before-win)))
          (set-window-start bw start)))))))

(defun claude-diff--reset ()
  "Restore the window layout that was active before the diff was shown."
  ;; Cancel timers
  (when claude-diff--scroll-timer
    (cancel-timer claude-diff--scroll-timer)
    (setq claude-diff--scroll-timer nil))
  (when claude-diff--auto-dismiss-timer
    (cancel-timer claude-diff--auto-dismiss-timer)
    (setq claude-diff--auto-dismiss-timer nil))
  ;; Kill diff buffers (Before/After)
  (dolist (buf (buffer-list))
    (when (or (string-prefix-p "*Before: " (buffer-name buf))
              (string-prefix-p "*After: " (buffer-name buf)))
      (kill-buffer buf)))
  ;; Restore the saved window configuration — this brings back all splits,
  ;; buffers, and window sizes exactly as they were before the diff.
  (when claude-diff--saved-wconf
    (ignore-errors (set-window-configuration claude-diff--saved-wconf)))
  (setq claude-diff--current-file nil
        claude-diff--saved-wconf nil))

;; ── Hook entry point ─────────────────────────────────────────────────

(defun claude-diff-from-hook (json-file)
  "Parse hook JSON-FILE, construct before/after buffers, and show diff."
  (let* ((json-object-type 'alist)
         (json-array-type 'list)
         (data (json-read-file json-file))
         (tool-name (alist-get 'tool_name data))
         (tool-input (alist-get 'tool_input data))
         (file-path (alist-get 'file_path tool-input)))
    (when (and file-path (file-exists-p file-path))
      (let* ((disk (with-temp-buffer
                     (insert-file-contents file-path)
                     (buffer-string)))
             (old-str (alist-get 'old_string tool-input))
             (new-str (alist-get 'new_string tool-input))
             (replace-all (alist-get 'replace_all tool-input))
             ;; Determine before/after regardless of whether the edit
             ;; has already been applied to disk
             (before nil)
             (after nil))
        (cond
         ((string= tool-name "Edit")
          (cond
           ;; Edit not yet applied — old_string found in disk
           ((cl-search old-str disk)
            (setq before disk)
            (setq after (if replace-all
                            (let ((result disk) (start 0))
                              (while (setq start (cl-search old-str result :start2 start))
                                (setq result (concat (substring result 0 start)
                                                     new-str
                                                     (substring result (+ start (length old-str)))))
                                (setq start (+ start (length new-str))))
                              result)
                          (let ((pos (cl-search old-str disk)))
                            (concat (substring disk 0 pos)
                                    new-str
                                    (substring disk (+ pos (length old-str))))))))
           ;; Edit already applied — new_string found in disk, reverse it
           ((cl-search new-str disk)
            (setq after disk)
            (setq before (let ((pos (cl-search new-str disk)))
                           (concat (substring disk 0 pos)
                                   old-str
                                   (substring disk (+ pos (length new-str)))))))))
         ((string= tool-name "Write")
          (let ((content (alist-get 'content tool-input)))
            (if (string= disk content)
                ;; Write already applied — no before available
                nil
              (setq before disk
                    after content)))))
        (when (and before after (not (string= before after)))
          (claude-diff-show file-path before after))))))

;; ── Display ──────────────────────────────────────────────────────────

(defun claude-diff-show (file before-content after-content)
  "Show 2-way diff for FILE with BEFORE-CONTENT and AFTER-CONTENT."
  ;; Save the full window configuration so reset can restore all splits/buffers.
  ;; Only save if we don't already have one (avoid overwriting with diff layout).
  (unless claude-diff--saved-wconf
    (setq claude-diff--saved-wconf (current-window-configuration)))
  ;; Kill any existing diff buffers from a prior review
  (dolist (buf (buffer-list))
    (when (or (string-prefix-p "*Before: " (buffer-name buf))
              (string-prefix-p "*After: " (buffer-name buf)))
      (kill-buffer buf)))
  (let* ((file (expand-file-name file))
         (_ (setq claude-diff--current-file file))
         (basename (file-name-nondirectory file))
         (before-buf (get-buffer-create (format "*Before: %s*" basename)))
         (after-buf (get-buffer-create (format "*After: %s*" basename)))
         (file-buf (find-file-noselect file t))
         (mode (buffer-local-value 'major-mode file-buf)))
    ;; Fill Before buffer
    (with-current-buffer before-buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert before-content)
        (set-buffer-modified-p nil)
        (setq buffer-read-only t)
        (when (fboundp mode) (funcall mode))))
    ;; Fill After buffer
    (with-current-buffer after-buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert after-content)
        (set-buffer-modified-p nil)
        (setq buffer-read-only t)
        (when (fboundp mode) (funcall mode))))
    ;; Highlight the differences
    (claude-diff--highlight before-buf after-buf)
    ;; Enable scroll sync on both buffers
    (dolist (buf (list before-buf after-buf))
      (with-current-buffer buf
        (add-hook 'window-scroll-functions #'claude-diff--on-scroll nil t)))
    ;; Take over the full frame: diff side-by-side in the top 2/3,
    ;; vterm popup in the bottom 1/3.  The saved wconf restores
    ;; everything on dismiss.
    (let ((claude-buf (seq-find (lambda (b)
                                  (string-prefix-p "*claude:" (buffer-name b)))
                                (buffer-list))))
      (delete-other-windows)
      (let* ((root (selected-window))
             (vterm-height (/ (frame-height) 3))
             (bottom-win (split-window root (- vterm-height) 'below))
             (right-win  (split-window root nil 'right)))
        (set-window-buffer root before-buf)
        (set-window-buffer right-win after-buf)
        ;; Show vterm in the bottom third
        (when claude-buf
          (set-window-buffer bottom-win claude-buf)
          (select-window bottom-win))))
    ;; Scroll to first change after windows settle
    (setq claude-diff--scroll-timer (run-with-timer 0.15 nil
      (lambda (ab bb)
        (when (and (buffer-live-p ab)
                   (get-buffer-window ab))
          (let* ((win (get-buffer-window ab))
                 (ov (with-current-buffer ab
                       (cl-find-if (lambda (o) (overlay-get o 'claude-diff))
                                   (overlays-in (point-min) (point-max)))))
                 (pos (and ov (overlay-start ov)))
                 (start (and pos (with-current-buffer ab
                                   (save-excursion (goto-char pos) (forward-line -3) (point))))))
            (when start
              (set-window-point win pos)
              (claude-diff--sync-windows start)
              ;; Also scroll the before buffer to match
              (when-let ((bw (get-buffer-window bb)))
                (set-window-start bw start))))))
      after-buf before-buf))
    ;; Auto-dismiss after 15s if PostToolUse never fires (user denied the edit).
    ;; The PostToolUse dismiss hook cancels this timer via claude-diff--reset.
    (when claude-diff--auto-dismiss-timer
      (cancel-timer claude-diff--auto-dismiss-timer))
    (setq claude-diff--auto-dismiss-timer
          (run-with-timer 15 nil #'claude-diff-dismiss))))

;; ── Navigation ───────────────────────────────────────────────────────

(defun claude-diff-next-change ()
  "Jump to the next highlighted change in the diff windows."
  (interactive)
  (when-let ((win (claude-diff--after-win)))
    (let* ((buf (window-buffer win))
           (cur (window-point win))
           (ovs (with-current-buffer buf
                  (sort (seq-filter (lambda (o) (overlay-get o 'claude-diff))
                                    (overlays-in (point-min) (point-max)))
                        (lambda (a b) (< (overlay-start a) (overlay-start b))))))
           (next (cl-find-if (lambda (o) (> (overlay-start o) cur)) ovs)))
      (if next
          (let* ((pos (overlay-start next))
                 (start (with-current-buffer buf
                          (save-excursion (goto-char pos) (forward-line -3) (point)))))
            (set-window-point win pos)
            (claude-diff--sync-windows start))
        (message "No more changes")))))

(defun claude-diff-prev-change ()
  "Jump to the previous highlighted change in the diff windows."
  (interactive)
  (when-let ((win (claude-diff--after-win)))
    (let* ((buf (window-buffer win))
           (cur (window-point win))
           (ovs (with-current-buffer buf
                  (sort (seq-filter (lambda (o) (overlay-get o 'claude-diff))
                                    (overlays-in (point-min) (point-max)))
                        (lambda (a b) (> (overlay-start a) (overlay-start b))))))
           (prev (cl-find-if (lambda (o) (< (overlay-start o) cur)) ovs)))
      (if prev
          (let* ((pos (overlay-start prev))
                 (start (with-current-buffer buf
                          (save-excursion (goto-char pos) (forward-line -3) (point)))))
            (set-window-point win pos)
            (claude-diff--sync-windows start))
        (message "No earlier changes")))))

(defun claude-diff-scroll-up ()
  "Scroll diff windows up without stealing focus."
  (interactive)
  (when-let ((win (claude-diff--after-win)))
    (let ((new-start (with-current-buffer (window-buffer win)
                       (save-excursion
                         (goto-char (window-start win))
                         (forward-line 5)
                         (point)))))
      (claude-diff--sync-windows new-start))))

(defun claude-diff-scroll-down ()
  "Scroll diff windows down without stealing focus."
  (interactive)
  (when-let ((win (claude-diff--after-win)))
    (let ((new-start (with-current-buffer (window-buffer win)
                       (save-excursion
                         (goto-char (window-start win))
                         (forward-line -5)
                         (point)))))
      (claude-diff--sync-windows new-start))))

;; ── Actions ──────────────────────────────────────────────────────────

(defun claude-diff-dismiss ()
  "Close diff view and restore vterm layout."
  (interactive)
  (claude-diff--reset))

(defun claude-diff-approve ()
  "Accept the changes and close the diff view."
  (interactive)
  (message "Changes approved for %s" (or claude-diff--current-file "file"))
  (claude-diff-dismiss))

(defun claude-diff-deny ()
  "Revert the file to HEAD and close the diff view."
  (interactive)
  (when claude-diff--current-file
    (let ((default-directory (string-trim (shell-command-to-string "git rev-parse --show-toplevel"))))
      (when (yes-or-no-p (format "Revert %s to HEAD? " (file-name-nondirectory claude-diff--current-file)))
        (call-process "git" nil nil nil "checkout" "HEAD" "--" claude-diff--current-file)
        (when-let ((buf (find-buffer-visiting claude-diff--current-file)))
          (with-current-buffer buf (revert-buffer t t t)))
        (message "Reverted %s to HEAD" (file-name-nondirectory claude-diff--current-file)))))
  (claude-diff-dismiss))

;; ── File watcher trigger ──────────────────────────────────────────────
;; The PermissionRequest hook writes JSON to this file.
;; Emacs watches it and triggers the diff display.

(defvar claude-diff--hook-dir
  (expand-file-name "claude-diff" (or (getenv "XDG_RUNTIME_DIR") "/tmp"))
  "Directory watched for Claude Code hook JSON files.")

(defvar claude-diff--hook-file
  (expand-file-name "input.json" claude-diff--hook-dir)
  "File written by the Claude Code PermissionRequest hook.")

(defvar claude-diff--file-watcher nil
  "File-notify descriptor for the hook JSON file.")

(defun claude-diff--on-hook-file-change (event)
  "Handle changes to the hook JSON file."
  (let ((action (nth 1 event)))
    (when (memq action '(changed created))
      (ignore-errors
        (claude-diff-from-hook claude-diff--hook-file)))))

(defun claude-diff-watch-start ()
  "Start watching for Claude Code hook JSON file changes."
  (interactive)
  (claude-diff-watch-stop)
  ;; Create dedicated directory so we only see our own events (not all of /tmp)
  (make-directory claude-diff--hook-dir t)
  (setq claude-diff--file-watcher
        (file-notify-add-watch claude-diff--hook-dir '(change) #'claude-diff--on-hook-file-change))
  (message "Claude diff watcher active on %s" claude-diff--hook-dir))

(defun claude-diff-watch-stop ()
  "Stop watching for hook file changes."
  (interactive)
  (when claude-diff--file-watcher
    (ignore-errors (file-notify-rm-watch claude-diff--file-watcher))
    (setq claude-diff--file-watcher nil)))

;; Auto-start watcher
(claude-diff-watch-start)

(provide 'claude-diff)
;;; claude-diff.el ends here
