package cmds

import (
	"fmt"
	"time"

	"emacs-doctor/internal/daemon"
	"emacs-doctor/internal/ui"
)

// Reset recovers to a single clean systemd-managed daemon. It refuses to run
// when any file buffer is unsaved unless --force is given (which discards them).
func Reset(args []string) error {
	force := false
	for _, a := range args {
		if a == "--force" {
			force = true
		}
	}

	ui.Header("Emacs daemon reset")

	if n, ok := daemon.UnsavedCount(); ok && n > 0 {
		if !force {
			ui.Bad(fmt.Sprintf("%d buffer(s) have unsaved changes — refusing to reset.", n))
			if files := daemon.UnsavedFiles(); files != "" && files != "nil" {
				ui.Info(files)
			}
			ui.Info("Save them (C-x s in Emacs) or re-run with --force to discard, then retry.")
			return fmt.Errorf("%d unsaved buffer(s)", n)
		}
		ui.Warn(fmt.Sprintf("%d unsaved buffer(s) — proceeding due to --force (changes will be LOST).", n))
	}

	ui.Info("stopping emacs.service ...")
	daemon.StopService()

	if killed := daemon.TermDaemons(); killed > 0 {
		time.Sleep(time.Second)
		daemon.KillDaemons()
		ui.Info(fmt.Sprintf("killed %d leftover daemon process(es)", killed))
	}

	for _, p := range daemon.RemoveStaleSockets() {
		ui.Info("removed stale socket: " + p)
	}

	daemon.ResetFailed()

	ui.Info("starting emacs.service ...")
	if err := daemon.StartService(); err != nil {
		ui.Bad("failed to start emacs.service — journalctl --user -u emacs -e")
		return err
	}

	// Doom can take several seconds to load; poll for the socket.
	for i := 0; i < 60; i++ {
		if daemon.Answers() {
			break
		}
		time.Sleep(500 * time.Millisecond)
	}
	if daemon.Answers() {
		ui.OK("daemon is up and answering")
	} else {
		ui.Bad("daemon started but not answering yet — journalctl --user -u emacs -e")
	}

	return Status(nil)
}
