package cmds

import (
	"fmt"
	"os"
	"os/user"
	"strconv"
	"strings"

	"tmux-helper/internal/ssh"
	"tmux-helper/internal/system"
)

// Status routes the 'status' subcommand. Phase 2 implemented uptime-fmt,
// loadavg, and a local-only user-host. Phase 6 upgrades user-host with
// SSH-aware detection (process tree walk + ssh -G + per-pane file cache).
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

// statusUserHost: when invoked with `pane_id pane_pid`, walks the pane's
// process tree for ssh/mosh and emits user@host[:port]. Falls back to local
// user@host if no ssh chain is found or args are missing.
func statusUserHost(args []string) error {
	if len(args) >= 2 {
		if conn := detectPaneSSH(args[0], args[1]); conn != nil {
			u := conn.User
			if u == "" {
				u = localUser()
			}
			if conn.Port != "" && conn.Port != "22" {
				fmt.Printf("%s@%s:%s\n", u, conn.Host, conn.Port)
			} else {
				fmt.Printf("%s@%s\n", u, conn.Host)
			}
			return nil
		}
	}
	host, _ := os.Hostname()
	fmt.Printf("%s@%s\n", localUser(), host)
	return nil
}

func localUser() string {
	if u, err := user.Current(); err == nil {
		return u.Username
	}
	return "user"
}

// detectPaneSSH returns the ssh connection a pane is currently on, or nil
// if the pane is local. Uses a 30s file cache keyed by (server_pid, pane_id).
func detectPaneSSH(paneID, panePIDStr string) *ssh.Connection {
	serverPID := os.Getppid()
	if cached, hit := ssh.Read(serverPID, paneID); hit {
		return cached
	}
	panePID, err := strconv.Atoi(panePIDStr)
	if err != nil {
		return nil
	}
	tree, err := system.PsTree()
	if err != nil {
		return nil
	}
	sshPID := system.FindSSH(tree, panePID)
	if sshPID == 0 {
		_ = ssh.Write(serverPID, paneID, nil)
		return nil
	}
	argsStr, err := system.ProcessArgs(sshPID)
	if err != nil || argsStr == "" {
		return nil
	}
	parts := strings.Fields(argsStr)
	if len(parts) < 2 {
		_ = ssh.Write(serverPID, paneID, nil)
		return nil
	}
	conn, err := ssh.Detect(parts[1:])
	if err != nil {
		_ = ssh.Write(serverPID, paneID, nil)
		return nil
	}
	_ = ssh.Write(serverPID, paneID, conn)
	return conn
}
