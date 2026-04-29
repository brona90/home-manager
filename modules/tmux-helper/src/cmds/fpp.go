package cmds

import (
	"fmt"
	"os/exec"

	"tmux-helper/internal/tmux"
)

func Fpp(args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: fpp <pane_id> <cwd>")
	}
	paneID, cwd := args[0], args[1]
	if _, err := exec.LookPath("fpp"); err != nil {
		return tmux.Run("display-message", "fpp not on PATH (install facebook-pathpicker)")
	}
	cmd := fmt.Sprintf("tmux capture-pane -p -t %q | fpp", paneID)
	return tmux.Run("new-window", "-c", cwd, "sh", "-c", cmd)
}
