# Pure function returning the experimental tmux config text. Imported from
# both modules/tmux/default.nix (when my.tmux.useHelper is true) and
# flake.nix's apps.tmux-experimental (parallel-server testing path).
#
# Phase 2: status bar wired to the Go helper (uptime/loadavg/user-host).
# Phase 3: copy-mode-vi clipboard binding + OSC 52 pass-through for SSH panes.
# Phase 4: theme + 38 keybindings reproducing gpakosz UX. Pure-tmux binds
#          fire directly; helper-dependent ones (maximize, toggle-mouse,
#          reload, clear-history, fpp, urlview) display a placeholder until
#          their Phase-5/Phase-7 implementations land.
{helperBin}: ''
  # --- Terminal ----------------------------------------------------------
  set -g default-terminal "tmux-256color"
  set -ag terminal-overrides ",xterm-256color:RGB"
  set -ag terminal-overrides ",*256col*:Tc"
  set -q -g status-utf8 on
  setw -q -g utf8 on

  # --- OSC 52 clipboard pass-through (SSH'd panes) -----------------------
  # \E]52;c;<base64>\007 lets a pane write to the local terminal's clipboard
  # via the terminal emulator -- so selecting text inside an SSH session
  # reaches your real clipboard without the helper round-tripping back.
  set -g set-clipboard on
  set -ag terminal-overrides ",*:Ms=\E]52;%p1%s;%p2%s\007"

  # --- Prefix / session basics -------------------------------------------
  set -g prefix C-a
  set -g prefix2 C-a
  unbind C-b
  bind C-a send-prefix
  set -g mouse on
  set -g history-limit 50000
  set -g base-index 1
  setw -g pane-base-index 1
  setw -g automatic-rename on
  set -g focus-events on
  set -g renumber-windows on
  set -g status-keys emacs
  setw -g mode-keys vi

  # --- Theme: 17-color gpakosz palette -----------------------------------
  # Pane borders + active focus
  set -g pane-border-style "fg=#444444"
  set -g pane-active-border-style "fg=#00afff"
  # Message line (when tmux echoes things to you)
  set -g message-style "fg=#000000,bg=#ffff00,bold"
  set -g message-command-style "fg=#ffff00,bg=#000000,bold"
  # Copy / choose modes
  setw -g mode-style "fg=#000000,bg=#ffff00,bold"
  # Status bar base
  set -g status on
  set -g status-interval 10
  set -g status-justify left
  set -g status-position bottom
  set -g status-style "fg=#8a8a8a,bg=#080808,none"
  set -g status-left-length 100
  set -g status-right-length 120
  # Window status (tabs in middle of status bar)
  setw -g window-status-style "fg=#8a8a8a,bg=#080808,none"
  setw -g window-status-current-style "fg=#000000,bg=#00afff,bold"
  setw -g window-status-activity-style "underscore"
  setw -g window-status-bell-style "fg=#ffff00,blink,bold"
  setw -g window-status-last-style "fg=#00afff,none"
  setw -g window-status-separator ""
  setw -g window-status-format        " #I #W#{?window_bell_flag,🔔,}#{?window_zoomed_flag,🔍,} "
  setw -g window-status-current-format " #I #W#{?window_zoomed_flag,🔍,} "
  # Clock-mode (prefix t)
  setw -g clock-mode-colour "#00afff"
  setw -g clock-mode-style 24

  # --- Status-left: ❐ session | up Nd Nh Nm ------------------------------
  # tmux's #{uptime_d/h/m} are native; no helper exec needed for uptime.
  set -g status-left "#[fg=#000000,bg=#ffff00,bold] ❐ #S #[fg=#ffff00,bg=#080808,nobold]#[fg=#8a8a8a,bg=#080808] up#{?uptime_d, #{uptime_d}d,}#{?uptime_h, #{uptime_h}h,}#{?uptime_m, #{uptime_m}m,} "

  # --- Status-right: prefix/sync | loadavg , %R , %d %b | user@host ------
  set -g status-right "#{?client_prefix,#[fg=#ffff00] ⌨ ,}#{?pane_synchronized,#[fg=#d70000] 🔒 ,}#[fg=#8a8a8a,bg=#080808] #(${helperBin} status loadavg) , %R , %d %b | #(${helperBin} status user-host) "

  # --- Keybindings -------------------------------------------------------
  # Reload (Phase 5: replace stub with helper reload subcommand)
  bind r run-shell "${helperBin} reload"

  # Global C-l clears history with screen redraw. gpakosz had this with a
  # 0.2s sleep + clear-history; will be wired through helper in Phase 5 so
  # the timing stays consistent across terminals.
  bind C-l run-shell "${helperBin} clear-history #{pane_id}"

  # Sessions
  bind C-c new-session
  bind C-f command-prompt -p "find session" "switch-client -t %%"
  bind BTab switch-client -l

  # Splits open in the same cwd as the active pane
  bind - split-window -v -c "#{pane_current_path}"
  bind _ split-window -h -c "#{pane_current_path}"

  # Pane navigation (vim keys, repeatable)
  bind -r h select-pane -L
  bind -r j select-pane -D
  bind -r k select-pane -U
  bind -r l select-pane -R

  # Swap panes
  bind > swap-pane -D
  bind < swap-pane -U

  # Resize (repeatable)
  bind -r H resize-pane -L 2
  bind -r J resize-pane -D 2
  bind -r K resize-pane -U 2
  bind -r L resize-pane -R 2

  # Window navigation
  bind -r C-h previous-window
  # prefix-C-l now bound to clear-history (above); use prefix-n for next-window
  bind Tab last-window

  # Zoom (Phase 5: maximize-pane via helper, gpakosz's prefix-+)
  bind + run-shell "${helperBin} maximize-pane #{session_name} #{pane_id}"

  # Mouse toggle (Phase 5)
  bind m run-shell "${helperBin} toggle-mouse"

  # vim-tmux-navigator: C-h/j/k/l globally. If the active pane's foreground
  # command is vim/nvim, the helper forwards C-w<dir> to that pane; otherwise
  # it does select-pane in the corresponding direction. The plan reassigned
  # the old global C-l (clear-history) to prefix-C-l above so this binding
  # can take it over.
  bind -n C-h run-shell "${helperBin} navigate left"
  bind -n C-j run-shell "${helperBin} navigate down"
  bind -n C-k run-shell "${helperBin} navigate up"
  bind -n C-l run-shell "${helperBin} navigate right"


  # File picker / urlview (Phase 7)
  bind F display-message "phase 7: fpp picker not yet wired"
  bind U display-message "phase 7: urlview not yet wired"

  # Copy mode: Enter to enter, vi-style selection
  bind Enter copy-mode
  bind -T copy-mode-vi v send -X begin-selection
  bind -T copy-mode-vi C-v send -X rectangle-toggle
  bind -T copy-mode-vi y send -X copy-pipe-and-cancel "${helperBin} clipboard copy"
  bind -T copy-mode-vi Escape send -X cancel
  bind -T copy-mode-vi H send -X start-of-line
  bind -T copy-mode-vi L send -X end-of-line

  # Prefix-y: pipe last buffer to clipboard via helper (matches gpakosz's
  # cross-platform y; the helper handles backend selection in one place).
  bind y run-shell "tmux save-buffer - | ${helperBin} clipboard copy"

  # Buffers
  bind b list-buffers
  bind p paste-buffer -p
  bind P choose-buffer
''
