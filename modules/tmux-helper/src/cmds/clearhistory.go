package cmds

import (
	"fmt"
	"time"

	"tmux-helper/internal/tmux"
)

// ClearHistory clears both the visible terminal (via send-keys C-l in the
// shell) and tmux's scrollback buffer. The 200ms gap between them lets the
// shell finish processing C-l so the redraw doesn't end up in the cleared
// scrollback.
func ClearHistory(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage: clear-history <pane_id>")
	}
	pane := args[0]
	if err := tmux.Run("send-keys", "-t", pane, "C-l"); err != nil {
		return err
	}
	time.Sleep(200 * time.Millisecond)
	return tmux.Run("clear-history", "-t", pane)
}
