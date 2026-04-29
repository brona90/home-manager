package cmds

import (
	"strings"

	"tmux-helper/internal/tmux"
)

// ToggleMouse flips the global `mouse` option and confirms via display-message.
func ToggleMouse(_ []string) error {
	cur, err := tmux.GlobalOption("mouse")
	if err != nil {
		return err
	}
	next := "on"
	if strings.TrimSpace(cur) == "on" {
		next = "off"
	}
	if err := tmux.SetGlobalOption("mouse", next); err != nil {
		return err
	}
	return tmux.Run("display-message", "mouse: "+next)
}
