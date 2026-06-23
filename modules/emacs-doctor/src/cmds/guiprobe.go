package cmds

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"emacs-doctor/internal/ui"
)

// GuiProbe measures GUI launch latency by timing how long an xeyes window takes
// to appear, repeated three times.
func GuiProbe(_ []string) error {
	ui.Header("GUI launch probe")
	if os.Getenv("DISPLAY") == "" && os.Getenv("WAYLAND_DISPLAY") == "" {
		ui.Warn("no DISPLAY/WAYLAND_DISPLAY — cannot probe GUI")
		return nil
	}
	if !haveCmd("xeyes") || !haveCmd("xwininfo") {
		ui.Warn("xeyes/xwininfo unavailable")
		return nil
	}

	for i := 1; i <= 3; i++ {
		start := time.Now()
		cmd := exec.Command("xeyes")
		if err := cmd.Start(); err != nil {
			ui.Warn("failed to launch xeyes: " + err.Error())
			return nil
		}
		deadline := start.Add(10 * time.Second)
		for time.Now().Before(deadline) {
			out, _ := exec.Command("xwininfo", "-root", "-tree").Output()
			if strings.Contains(strings.ToLower(string(out)), "xeyes") {
				break
			}
			time.Sleep(50 * time.Millisecond)
		}
		ms := time.Since(start).Milliseconds()
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
		_ = cmd.Wait()
		ui.Info(fmt.Sprintf("run %d: %d ms", i, ms))
	}
	ui.Info("(< ~500ms is healthy; multi-second points to CPU contention or software GL)")
	return nil
}
