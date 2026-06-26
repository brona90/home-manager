// Command emacs-doctor inspects, resets, and monitors the systemd-managed Emacs
// daemon, with WSL/system health context. It mirrors the tmux-helper layout:
// a map-based subcommand dispatch here, one file per command under cmds/, and
// shared logic under internal/.
//
// The failure it targets: a stray standalone `emacs --daemon` grabs the server
// socket, the managed `--fg-daemon` can never bind it, and Restart=on-failure
// loops forever, pegging a core. See cmds.Reset for the recovery.
package main

import (
	"fmt"
	"os"

	"emacs-doctor/cmds"
)

// version is set at build time via -ldflags -X main.version=...
var version = "dev"

type subcommandFunc func(args []string) error

var subcommands = map[string]subcommandFunc{
	"status":    cmds.Status,
	"reset":     cmds.Reset,
	"fix":       cmds.Reset,
	"gui-probe": cmds.GuiProbe,
	"watch":     cmds.Watch,
	"version":   cmdVersion,
}

func main() {
	name := "status"
	var args []string
	if len(os.Args) >= 2 {
		name = os.Args[1]
		args = os.Args[2:]
	}

	switch name {
	case "-h", "--help", "help":
		usage(os.Stdout)
		return
	}

	fn, ok := subcommands[name]
	if !ok {
		fmt.Fprintf(os.Stderr, "emacs-doctor: unknown command %q\n\n", name)
		usage(os.Stderr)
		os.Exit(2)
	}

	if err := fn(args); err != nil {
		fmt.Fprintf(os.Stderr, "emacs-doctor %s: %v\n", name, err)
		os.Exit(1)
	}
}

func cmdVersion(_ []string) error {
	fmt.Println(version)
	return nil
}

func usage(w *os.File) {
	fmt.Fprint(w, `emacs-doctor — inspect, reset, and monitor the Emacs daemon + WSL health

usage: emacs-doctor [command]

commands:
  status            health dashboard: daemon state, orphan/socket-squat
                    detection, system load, GPU/GL, GUI hint (default)
  reset [--force]   recover to one clean systemd-managed daemon. Refuses if any
                    buffer is unsaved unless --force (which discards them).
  gui-probe [-- cmd...]
                    time a real GUI app's launch→first-window (e.g.
                    'gui-probe -- emacsclient -c'); no cmd = xeyes X11 floor.
                    Reports load average — the dominant factor on WSL.
  watch [seconds]   re-run status on an interval (default 5s)
  version           print version
  help              show this help
`)
}
