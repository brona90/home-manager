# Pure function returning the experimental tmux config text. Imported from
# both modules/tmux/default.nix (when my.tmux.useHelper is true) and
# flake.nix's apps.tmux-experimental (parallel-server testing path).
#
# Phase 2: status bar wired to the Go helper.
# Phase 3: copy-mode-vi clipboard binding + OSC 52 pass-through for SSH panes.
{helperBin}: ''
  # Terminal + UTF-8
  set -g default-terminal "tmux-256color"
  set -ag terminal-overrides ",xterm-256color:RGB"
  set -ag terminal-overrides ",*256col*:Tc"
  set -q -g status-utf8 on
  setw -q -g utf8 on

  # OSC 52 clipboard pass-through. \E]52;c;<base64>\007 lets a remote pane
  # write to the local terminal's clipboard via the terminal emulator -- so
  # selecting text inside an SSH session into a tmux pane reaches your real
  # clipboard without needing the helper to ssh back. Enabled at the tmux
  # layer with set-clipboard on, advertised to the terminal via Ms.
  set -g set-clipboard on
  set -ag terminal-overrides ",*:Ms=\E]52;%p1%s;%p2%s\007"

  # Match gpakosz prefix
  set -g prefix C-a
  unbind C-b
  bind C-a send-prefix

  set -g mouse on
  set -g history-limit 50000

  # vi keys in copy-mode. y pipes the active selection through the helper,
  # which writes to whichever clipboard backend it detected (xclip/xsel/
  # wl-copy/pbcopy/clip.exe). copy-pipe-and-cancel exits copy-mode after.
  set -g mode-keys vi
  bind -T copy-mode-vi v send -X begin-selection
  bind -T copy-mode-vi C-v send -X rectangle-toggle
  bind -T copy-mode-vi y send -X copy-pipe-and-cancel "${helperBin} clipboard copy"
  bind -T copy-mode-vi Escape send -X cancel

  # Status bar -- each #(...) is one helper exec per status-interval (10s).
  set -g status on
  set -g status-interval 10
  set -g status-justify left
  set -g status-left-length 100
  set -g status-right-length 120
  set -g status-left  ' #S | up #(${helperBin} status uptime-fmt) '
  set -g status-right ' #(${helperBin} status loadavg) | #(${helperBin} status user-host) | %R '
''
