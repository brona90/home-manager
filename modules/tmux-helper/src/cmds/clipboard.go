package cmds

import (
	"fmt"
	"os"

	"tmux-helper/internal/clipboard"
)

// Clipboard routes the 'clipboard' subcommand. Today only 'copy' is wired;
// future phases may add 'paste' if we need it for keybind round-trips.
func Clipboard(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: clipboard <copy>")
	}
	switch args[0] {
	case "copy":
		return clipboardCopy()
	default:
		return fmt.Errorf("unknown clipboard subcommand: %s", args[0])
	}
}

func clipboardCopy() error {
	if err := clipboard.Copy(os.Stdin); err != nil {
		return err
	}
	return nil
}
