package cmds

import (
	"fmt"
	"strings"

	"tmux-helper/internal/tmux"
)

// User-option keys we use as cross-invocation state on the tmux server. Each
// is namespaced with @ so tmux treats it as a user option (not a built-in).
const (
	optMaxSession = "@maximized_pane_session"
	optMaxPaneID  = "@maximized_pane_id"
	optMaxOrigin  = "@maximized_pane_origin_window"
	optMaxMarker  = "@maximized_pane_marker_window"
)

// MaximizePane toggles a "fill the window" state for the named pane.
//
// Enter: break-pane the pane out into a fresh window, stash the origin
// window id so we can restore later. Exit: join-pane back, kill the marker
// window, clear state. Unlike tmux's native `prefix-z` (resize-pane -Z), the
// pane's contents survive the round trip and can be operated on as a normal
// window while maximized.
func MaximizePane(args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: maximize-pane <session> <pane_id>")
	}
	sess, paneID := args[0], args[1]

	stored := strings.TrimSpace(maybeOpt(optMaxPaneID))
	if stored == "" {
		return enterMaximize(sess, paneID)
	}
	return exitMaximize(
		stored,
		strings.TrimSpace(maybeOpt(optMaxOrigin)),
		strings.TrimSpace(maybeOpt(optMaxMarker)),
	)
}

// maybeOpt returns the option's value, "" if unset. tmux returns non-zero
// when a user option isn't set globally; we treat that as absent.
func maybeOpt(name string) string {
	v, _ := tmux.GlobalOption(name)
	return v
}

func enterMaximize(sess, paneID string) error {
	originWin, err := tmux.DisplayMessage("#{window_id}")
	if err != nil {
		return fmt.Errorf("reading current window: %w", err)
	}
	originWin = strings.TrimSpace(originWin)

	markerWin, err := tmux.OutputTrim(
		"break-pane", "-s", paneID, "-d", "-P", "-F", "#{window_id}",
	)
	if err != nil {
		return fmt.Errorf("break-pane: %w", err)
	}
	markerWin = strings.TrimSpace(markerWin)

	for _, kv := range [][2]string{
		{optMaxSession, sess},
		{optMaxPaneID, paneID},
		{optMaxOrigin, originWin},
		{optMaxMarker, markerWin},
	} {
		if err := tmux.SetGlobalOption(kv[0], kv[1]); err != nil {
			return err
		}
	}
	return tmux.Run("select-window", "-t", markerWin)
}

func exitMaximize(paneID, originWin, markerWin string) error {
	defer clearMaximizeState()

	wins, err := tmux.OutputTrim("list-windows", "-aF", "#{window_id}")
	if err != nil {
		return err
	}
	hasMarker := false
	hasOrigin := false
	for _, w := range strings.Split(wins, "\n") {
		switch w {
		case markerWin:
			hasMarker = true
		case originWin:
			hasOrigin = true
		}
	}
	if !hasMarker {
		return tmux.Run("display-message", "maximize: marker window gone, state cleared")
	}
	if !hasOrigin {
		// Origin gone -- restoring would orphan the pane. Leave the marker as a
		// regular window and clear state. User keeps their work; they can deal.
		return tmux.Run("display-message", "maximize: origin window gone, marker kept as-is")
	}

	if err := tmux.Run("join-pane", "-s", paneID, "-t", originWin); err != nil {
		return fmt.Errorf("join-pane: %w", err)
	}
	// Marker window is now empty; tmux usually closes it automatically, but
	// kill-window is idempotent enough to be safe even if it's already gone.
	_ = tmux.Run("kill-window", "-t", markerWin)
	return nil
}

func clearMaximizeState() {
	for _, k := range []string{optMaxSession, optMaxPaneID, optMaxOrigin, optMaxMarker} {
		_ = tmux.SetGlobalOption(k, "")
	}
}
