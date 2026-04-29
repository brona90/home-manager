package cmds

import (
	"fmt"
	"strings"

	"tmux-helper/internal/tmux"
)

// Navigate is the vim-tmux-navigator equivalent: if the active pane's
// foreground command is vim/nvim, forward C-w<dir> to that pane so vim's
// own window navigation handles it. Otherwise, select the tmux pane in the
// given direction.
//
// The bind in conf-experimental.nix wires global C-h/C-j/C-k/C-l to this,
// overriding the older global-C-l clear-history bind (which moved to
// prefix-C-l in this phase).
func Navigate(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage: navigate <left|down|up|right>")
	}
	tmuxFlag, vimKey, ok := navigateKeys(args[0])
	if !ok {
		return fmt.Errorf("unknown direction: %s", args[0])
	}

	cmd, err := tmux.DisplayMessage("#{pane_current_command}")
	if err != nil {
		return err
	}
	if isVim(strings.TrimSpace(cmd)) {
		return tmux.Run("send-keys", "C-w", vimKey)
	}
	return tmux.Run("select-pane", tmuxFlag)
}

func navigateKeys(dir string) (tmuxFlag, vimKey string, ok bool) {
	switch dir {
	case "left":
		return "-L", "h", true
	case "down":
		return "-D", "j", true
	case "up":
		return "-U", "k", true
	case "right":
		return "-R", "l", true
	}
	return "", "", false
}

// isVim returns true for command names that represent a vim/neovim instance
// in which we want to forward C-w<dir> as window navigation.
func isVim(cmd string) bool {
	switch cmd {
	case "vim", "vi", "nvim", "neovim", "vimr", "vimx", "nvim-qt":
		return true
	}
	return false
}
