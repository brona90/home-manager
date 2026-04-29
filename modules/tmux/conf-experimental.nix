# Pure function returning the experimental tmux config text. Imported from
# both modules/tmux/default.nix (when my.tmux.useHelper is true) and
# flake.nix's apps.tmux-experimental (parallel-server testing path).
#
# Phase 2: status bar wired to the Go helper. Bindings, theme, clipboard, and
# SSH detection land in subsequent phases.
{helperBin}: ''
  # Terminal + UTF-8
  set -g default-terminal "tmux-256color"
  set -ag terminal-overrides ",xterm-256color:RGB"
  set -ag terminal-overrides ",*256col*:Tc"
  set -q -g status-utf8 on
  setw -q -g utf8 on

  # Match gpakosz prefix
  set -g prefix C-a
  unbind C-b
  bind C-a send-prefix

  set -g mouse on
  set -g history-limit 50000

  # Status bar -- each #(...) is one helper exec per status-interval (10s).
  set -g status on
  set -g status-interval 10
  set -g status-justify left
  set -g status-left-length 100
  set -g status-right-length 120
  set -g status-left  ' #S | up #(${helperBin} status uptime-fmt) '
  set -g status-right ' #(${helperBin} status loadavg) | #(${helperBin} status user-host) | %R '
''
