# Pure function returning the experimental tmux config text. Imported from
# both modules/tmux/default.nix (when my.tmux.useHelper is true) and
# flake.nix's apps.tmux-experimental (parallel-server testing path).
#
# Phase 2: status bar wired to the Go helper (uptime/loadavg/user-host).
# Phase 3: copy-mode-vi clipboard binding + OSC 52 pass-through for SSH panes.
# Phase 4: theme + 38 keybindings reproducing gpakosz UX.
# Phase 5: helper-driven binds (reload, clear-history, maximize, toggle-mouse,
#          vim-tmux-navigator).
# Phase 5.1: dynamic themes (gpakosz, catppuccin-mocha, tokyonight, gruvbox,
#            rose-pine, nord, dracula, solarized-dark, kanagawa). Helper
#            applies the chosen theme at conf load and on prefix-T cycle.
{
  helperBin,
  defaultThemePreset,
}: ''
  # --- Terminal ----------------------------------------------------------
  set -g default-terminal "tmux-256color"
  set -ag terminal-overrides ",xterm-256color:RGB"
  set -ag terminal-overrides ",*256col*:Tc"
  set -q -g status-utf8 on
  setw -q -g utf8 on

  # --- OSC 52 clipboard pass-through (SSH'd panes) -----------------------
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
  set -g status on
  set -g status-interval 10
  set -g status-justify left
  set -g status-position bottom
  set -g status-left-length 100
  set -g status-right-length 120
  setw -g window-status-separator ""
  setw -g window-status-format        " #I #W#{?window_bell_flag,🔔,}#{?window_zoomed_flag,🔍,} "
  setw -g window-status-current-format " #I #W#{?window_zoomed_flag,🔍,} "
  setw -g clock-mode-style 24

  # --- Keybindings -------------------------------------------------------
  # Reload via helper (TMUX_HELPER_CONF env var supplies the path).
  bind r run-shell "${helperBin} reload"

  # Clear-history: send-keys C-l, sleep 200ms, clear-history (helper does
  # this with proper timing so the redraw doesn't end up in cleared scroll).
  bind C-l run-shell "${helperBin} clear-history #{pane_id}"

  # Sessions
  bind C-c new-session
  bind C-f command-prompt -p "find session" "switch-client -t %%"
  bind BTab switch-client -l

  # Splits in same cwd
  bind - split-window -v -c "#{pane_current_path}"
  bind _ split-window -h -c "#{pane_current_path}"

  # Pane navigation (vim keys, repeatable)
  bind -r h select-pane -L
  bind -r j select-pane -D
  bind -r k select-pane -U
  bind -r l select-pane -R

  # Swap
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

  # Maximize-pane (gpakosz prefix-+: break-pane out, restore on second press)
  bind + run-shell "${helperBin} maximize-pane #{session_name} #{pane_id}"

  # Mouse toggle
  bind m run-shell "${helperBin} toggle-mouse"

  # Theme cycle (prefix T) -- iterates sorted theme list, persists choice in
  # @tmux_theme_preset on the tmux server. Themes ship as a JSON read at
  # runtime (TMUX_HELPER_THEMES env var, set declaratively via Nix).
  bind T run-shell "${helperBin} theme cycle"

  # vim-tmux-navigator: C-h/j/k/l globally. Helper detects vim/nvim in the
  # active pane and forwards C-w<dir>; otherwise select-pane.
  bind -n C-h run-shell "${helperBin} navigate left"
  bind -n C-j run-shell "${helperBin} navigate down"
  bind -n C-k run-shell "${helperBin} navigate up"
  bind -n C-l run-shell "${helperBin} navigate right"

  # File picker / urlview (Phase 7)
  bind F display-message "phase 7: fpp picker not yet wired"
  bind U display-message "phase 7: urlview not yet wired"

  # Copy mode
  bind Enter copy-mode
  bind -T copy-mode-vi v send -X begin-selection
  bind -T copy-mode-vi C-v send -X rectangle-toggle
  bind -T copy-mode-vi y send -X copy-pipe-and-cancel "${helperBin} clipboard copy"
  bind -T copy-mode-vi Escape send -X cancel
  bind -T copy-mode-vi H send -X start-of-line
  bind -T copy-mode-vi L send -X end-of-line

  # Prefix-y: pipe last buffer to clipboard via helper
  bind y run-shell "tmux save-buffer - | ${helperBin} clipboard copy"

  # Buffers
  bind b list-buffers
  bind p paste-buffer -p
  bind P choose-buffer

  # --- Apply default theme on conf load ----------------------------------
  # Sets all theme-related options (status-left, status-right, palette, etc.)
  # via the helper which reads $TMUX_HELPER_THEMES (set via home.sessionVars).
  run-shell "${helperBin} theme apply ${defaultThemePreset}"
''
