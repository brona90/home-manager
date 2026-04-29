package cmds

import (
	"fmt"
	"os/exec"

	"tmux-helper/internal/tmux"
)

func Urlview(args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: urlview <pane_id> <cwd>")
	}
	paneID, cwd := args[0], args[1]

	tool := ""
	for _, candidate := range []string{"urlscan", "urlview"} {
		if _, err := exec.LookPath(candidate); err == nil {
			tool = candidate
			break
		}
	}
	if tool == "" {
		return tmux.Run("display-message", "urlscan/urlview not on PATH")
	}
	cmd := fmt.Sprintf("tmux capture-pane -p -t %q | %s", paneID, tool)
	return tmux.Run("new-window", "-c", cwd, "sh", "-c", cmd)
}
