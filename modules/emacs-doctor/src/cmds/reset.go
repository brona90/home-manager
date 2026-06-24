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

	n, ok := daemon.UnsavedCount()
	switch {
	case ok && n > 0:
		if !force {
			ui.Bad(fmt.Sprintf("%d buffer(s) have unsaved changes — refusing to reset.", n))
			if files := daemon.UnsavedFiles(); files != "" && files != "nil" {
				ui.Info(files)
			}
			ui.Info("Save them (C-x s in Emacs) or re-run with --force to discard, then retry.")
			return fmt.Errorf("%d unsaved buffer(s)", n)
		}
		ui.Warn(fmt.Sprintf("%d unsaved buffer(s) — proceeding due to --force (changes will be LOST).", n))
	case !ok && len(daemon.DaemonProcs()) > 0:
		// A daemon process exists but isn't answering emacsclient, so we can't
		// read its buffers — we cannot rule out unsaved work. Don't silently
		// kill it; require --force. (When no daemon exists at all we fall
		// through and proceed: there's nothing to lose, and reset's job is to
		// bring one back up.)
		if !force {
			ui.Bad("a daemon process is running but not answering emacsclient — cannot check for unsaved buffers.")
			ui.Info("Re-run with --force if you accept possibly losing unsaved work.")
			return fmt.Errorf("unsaved state unknown (daemon not answering)")
		}
		ui.Warn("daemon not answering; proceeding due to --force (unsaved work may be LOST).")
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
	if !daemon.Answers() {
		ui.Bad("daemon started but not answering yet — journalctl --user -u emacs -e")
		_ = Status(nil)
		return fmt.Errorf("daemon not answering after restart")
	}
	ui.OK("daemon is up and answering")
	return Status(nil)
}
