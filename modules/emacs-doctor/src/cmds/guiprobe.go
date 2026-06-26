package cmds

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"syscall"
	"time"

	"emacs-doctor/internal/sys"
	"emacs-doctor/internal/ui"
)

var winIDRe = regexp.MustCompile(`0x[0-9a-fA-F]+`)

// windowIDs returns the set of X11 window IDs currently in the tree. Note: this
// sees XWayland (X11) windows only — under WSLg most apps go through XWayland,
// but a pure-Wayland app's window won't be detected.
func windowIDs() map[string]bool {
	ids := map[string]bool{}
	out, err := exec.Command("xwininfo", "-root", "-tree").Output()
	if err != nil {
		return ids
	}
	for _, m := range winIDRe.FindAllString(string(out), -1) {
		ids[m] = true
	}
	return ids
}

// waitForNewWindow polls until a window ID appears that wasn't in `before`,
// returning the elapsed time since start. It bails out early if `done` fires
// (the launched process exited without mapping a window).
func waitForNewWindow(before map[string]bool, start time.Time, timeout time.Duration, done <-chan struct{}) (time.Duration, bool) {
	deadline := start.Add(timeout)
	for time.Now().Before(deadline) {
		for id := range windowIDs() {
			if !before[id] {
				return time.Since(start), true
			}
		}
		select {
		case <-done:
			return 0, false
		case <-time.After(50 * time.Millisecond):
		}
	}
	return 0, false
}

// launchAndTime starts argv, measures launch→first-new-window, then tears the
// process group down. mapped is false if no window appeared before timeout.
func launchAndTime(argv []string, timeout time.Duration) (elapsed time.Duration, mapped bool, err error) {
	before := windowIDs()
	start := time.Now()
	cmd := exec.Command(argv[0], argv[1:]...)
	// Own process group so we can reap children the app forks.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		return 0, false, err
	}

	done := make(chan struct{})
	go func() {
		_ = cmd.Wait()
		close(done)
	}()

	elapsed, mapped = waitForNewWindow(before, start, timeout, done)

	if cmd.Process != nil {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		_ = cmd.Process.Kill()
	}
	<-done // reap
	return elapsed, mapped, nil
}

// GuiProbe times how long a real GUI app takes to map its first window. Given a
// command it launches it and reports launch→first-window wall-clock; with no
// command it falls back to xeyes as an X11 round-trip FLOOR (not a real-app
// measurement). It always reports load average first, since GUI launch time on
// WSL is dominated by system load.
func GuiProbe(args []string) error {
	ui.Header("GUI launch probe")

	if os.Getenv("DISPLAY") == "" && os.Getenv("WAYLAND_DISPLAY") == "" {
		ui.Warn("no DISPLAY/WAYLAND_DISPLAY — cannot probe GUI")
		return nil
	}
	if !haveCmd("xwininfo") {
		ui.Warn("xwininfo unavailable — cannot detect windows")
		return nil
	}
	if len(args) > 0 && args[0] == "--" {
		args = args[1:]
	}

	// Load is the dominant factor — surface it before any number.
	if one, triple, ok := sys.LoadAvg(); ok {
		cores := sys.Cores()
		ui.Info(fmt.Sprintf("load average: %s (cores: %d)", triple, cores))
		if one > float64(cores) {
			ui.Warn("system is under load — launch times are inflated; re-measure when idle")
		}
	}

	if len(args) == 0 {
		return probeFloor()
	}
	return probeApp(args)
}

func probeApp(argv []string) error {
	if !haveCmd(argv[0]) {
		ui.Warn("command not found: " + argv[0])
		return nil
	}
	ui.Info(fmt.Sprintf("launching %q; timing until its first window maps…", strings.Join(argv, " ")))
	elapsed, mapped, err := launchAndTime(argv, 60*time.Second)
	if err != nil {
		ui.Bad("failed to launch: " + err.Error())
		return fmt.Errorf("launch %s: %w", argv[0], err)
	}
	if !mapped {
		ui.Bad("no new window appeared within 60s (app exited early, maps no window, or is pure-Wayland)")
		return fmt.Errorf("no window mapped for %s", argv[0])
	}
	ui.OK(fmt.Sprintf("%s: first window in %d ms", argv[0], elapsed.Milliseconds()))
	ui.Info("(launch→first-window wall-clock — includes toolkit/GL/portal/plugin init)")
	return nil
}

func probeFloor() error {
	if !haveCmd("xeyes") {
		ui.Warn("no app given and xeyes unavailable — pass one: emacs-doctor gui-probe -- <cmd>")
		return nil
	}
	ui.Info("no app given — measuring the X11 round-trip FLOOR with xeyes (NOT real-app latency)")
	elapsed, mapped, err := launchAndTime([]string{"xeyes"}, 15*time.Second)
	if err != nil {
		ui.Warn("failed to launch xeyes: " + err.Error())
		return nil
	}
	if mapped {
		ui.Info(fmt.Sprintf("xeyes (X11 floor): %d ms", elapsed.Milliseconds()))
	} else {
		ui.Warn("xeyes mapped no window within 15s")
	}
	ui.Info("Real GTK/Qt/Electron apps add toolkit + GStreamer/GL plugin-registry + portal")
	ui.Info("init on top of this and scale with load. Measure a real app: gui-probe -- <cmd>")
	return nil
}
