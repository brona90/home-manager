package cmds

import (
	"fmt"
	"strconv"
	"time"

	"emacs-doctor/internal/ui"
)

// Watch re-runs the status dashboard on an interval (default 5s) until
// interrupted. The optional first arg sets the interval in seconds.
func Watch(args []string) error {
	interval := 5
	if len(args) > 0 {
		if n, err := strconv.Atoi(args[0]); err == nil && n > 0 {
			interval = n
		}
	}
	for {
		fmt.Print("\033[2J\033[H") // clear screen, home cursor
		fmt.Println(ui.Dim(fmt.Sprintf("emacs-doctor — every %ds (Ctrl-C to stop)", interval)))
		_ = Status(nil)
		time.Sleep(time.Duration(interval) * time.Second)
	}
}
