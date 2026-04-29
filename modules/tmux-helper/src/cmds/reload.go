package cmds

import (
	"fmt"
	"os"

	"tmux-helper/internal/tmux"
)

// Reload sources the experimental tmux conf. The conf path is set by the
// experimental conf itself at load-time into TMUX_HELPER_CONF (a tmux global
// environment variable) so the bind can stay path-agnostic.
func Reload(_ []string) error {
	conf := os.Getenv("TMUX_HELPER_CONF")
	if conf == "" {
		return fmt.Errorf("TMUX_HELPER_CONF not set; cannot determine conf path")
	}
	if err := tmux.Run("source-file", conf); err != nil {
		return err
	}
	return tmux.Run("display-message", "sourced "+conf)
}
