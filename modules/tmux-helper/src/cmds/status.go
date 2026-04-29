package cmds

import (
	"fmt"
	"os"
	"os/user"

	"tmux-helper/internal/system"
)

// Status routes the 'status' subcommand. Phase 2 implements uptime-fmt,
// loadavg, and a local-only user-host. Phase 5 will replace user-host's
// implementation with SSH-aware detection.
func Status(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: status <uptime-fmt|loadavg|user-host> [args...]")
	}
	switch args[0] {
	case "uptime-fmt":
		return statusUptimeFmt()
	case "loadavg":
		return statusLoadavg()
	case "user-host":
		return statusUserHost(args[1:])
	default:
		return fmt.Errorf("unknown status subcommand: %s", args[0])
	}
}

func statusUptimeFmt() error {
	d, err := system.Uptime()
	if err != nil {
		return err
	}
	fmt.Println(system.FormatUptimeShort(d))
	return nil
}

func statusLoadavg() error {
	la, err := system.LoadAvg()
	if err != nil {
		return err
	}
	fmt.Printf("%.2f %.2f %.2f\n", la[0], la[1], la[2])
	return nil
}

func statusUserHost(_ []string) error {
	// Phase 5 takes pane_pid + pane_tty args and walks the process tree to
	// detect SSH/mosh sessions. For Phase 2, just emit local user@host so the
	// status bar renders something sensible.
	u, err := user.Current()
	if err != nil {
		return err
	}
	host, err := os.Hostname()
	if err != nil {
		return err
	}
	fmt.Printf("%s@%s\n", u.Username, host)
	return nil
}
