package cmds

import (
	"fmt"
	"strconv"

	"emacs-doctor/internal/daemon"
	"emacs-doctor/internal/sys"
	"emacs-doctor/internal/ui"
)

// Status prints the daemon + system health dashboard. It takes no args.
func Status(_ []string) error {
	statusEmacs()
	statusSystem()
	return nil
}

func statusEmacs() {
	ui.Header("Emacs daemon")
	st, err := daemon.QueryStatus()

	if err != nil {
		ui.Warn("service: unknown (" + err.Error() + ")")
	} else {
		statusService(st)
	}

	managed, orphans, unclassified := daemon.Classify(daemon.DaemonProcs(), st)
	if managed != 0 {
		ui.OK(fmt.Sprintf("managed daemon process PID %d", managed))
	}
	if len(orphans) > 0 {
		ui.Bad(fmt.Sprintf("orphan daemon(s): %s — not managed by systemd (socket squatter; run: emacs-doctor reset)", joinInts(orphans)))
	}
	if len(unclassified) > 0 {
		ui.Warn(fmt.Sprintf("daemon process(es) PID %s — whether systemd manages it is unknown (service state unreadable)", joinInts(unclassified)))
	}

	if pid, ok := daemon.SocketOwnerPID(); ok {
		switch {
		case !st.Known:
			ui.Info(fmt.Sprintf("server socket owned by PID %d (managed MainPID unknown)", pid))
		case pid == st.MainPID:
			ui.OK(fmt.Sprintf("server socket owned by the managed daemon (PID %d)", pid))
		default:
			ui.Bad(fmt.Sprintf("server socket owned by PID %d, not managed MainPID=%d (deadlock; run: emacs-doctor reset)", pid, st.MainPID))
		}
		nbuf, nbufOK := daemon.OpenFileBuffers()
		nmod, nmodOK := daemon.UnsavedCount()
		ui.Info(bufferSummary(nbuf, nbufOK, nmod, nmodOK))
	} else {
		ui.Warn("no daemon answering emacsclient")
	}

	if st.NRestarts >= 5 {
		ui.Bad(fmt.Sprintf("high restart count (%d) — crash loop; run: emacs-doctor reset", st.NRestarts))
	}
}

// bufferSummary renders the buffer counts. A failed query prints "unknown",
// never 0: "unsaved: 0" reads as "safe to reset".
func bufferSummary(nbuf int, nbufOK bool, nmod int, nmodOK bool) string {
	count := func(n int, ok bool) string {
		if !ok {
			return "unknown"
		}
		return strconv.Itoa(n)
	}
	return fmt.Sprintf("open file buffers: %s (unsaved: %s)", count(nbuf, nbufOK), count(nmod, nmodOK))
}

// statusService prints the unit state line for a successfully read Status.
func statusService(st daemon.Status) {
	switch st.ActiveState {
	case "active":
		ui.OK(fmt.Sprintf("service: active (%s), MainPID=%d, NRestarts=%s", st.SubState, st.MainPID, nrStr(st.NRestarts)))
	case "activating":
		ui.Warn(fmt.Sprintf("service: activating (%s) — starting or crash-looping; NRestarts=%s", st.SubState, nrStr(st.NRestarts)))
	case "failed":
		ui.Bad("service: failed — journalctl --user -u emacs -e")
	case "":
		ui.Warn("service: unknown")
	default:
		ui.Warn("service: " + st.ActiveState)
	}
}

func statusSystem() {
	ui.Header("System (WSL) health")
	cores := sys.Cores()
	if one, triple, ok := sys.LoadAvg(); ok {
		ui.Info(fmt.Sprintf("load average: %s   (cores: %d)", triple, cores))
		if one > float64(cores) {
			ui.Warn(fmt.Sprintf("1-min load (%.2f) exceeds core count (%d) — CPU saturated", one, cores))
		} else {
			ui.OK("load within core budget")
		}
	}
	fmt.Println("  memory:")
	for _, l := range sys.MemSummary() {
		ui.Info(l)
	}

	ui.Header("Top CPU")
	for _, l := range sys.TopCPU(6) {
		ui.Info(l)
	}
	if cpu, ok := sys.OllamaCPU(); ok {
		ui.Info(fmt.Sprintf("note: ollama running (~%.0f%% CPU) — local embeddings/LLM; transient bursts are normal", cpu))
	}

	ui.Header("Graphics (WSLg)")
	ui.Info(fmt.Sprintf("DISPLAY=%s  WAYLAND_DISPLAY=%s", envOr("DISPLAY", "<unset>"), envOr("WAYLAND_DISPLAY", "<unset>")))
	if sys.HasHardwareGL() {
		ui.OK("Mesa d3d12 driver present — hardware GL via WSLg")
	} else {
		ui.Warn("no d3d12_dri.so — GL may fall back to software (llvmpipe)")
	}
	if gpu, ok := sys.GPU(); ok {
		ui.OK("GPU: " + gpu)
	} else {
		ui.Info("nvidia-smi not available")
	}
	ui.Info("tip: 'emacs-doctor gui-probe' measures actual GUI launch latency")
}
