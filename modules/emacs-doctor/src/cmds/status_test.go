package cmds

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// fakeBins puts executable shell scripts first on PATH, one per name.
func fakeBins(t *testing.T, scripts map[string]string) {
	t.Helper()
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("sh not on PATH")
	}
	dir := t.TempDir()
	for name, body := range scripts {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// fakeDaemon starts a real process whose /proc cmdline carries --fg-daemon,
// so DaemonProcs() accepts the PID the fake pgrep reports. The trailing `:`
// stops sh exec-ing sleep in place, which would drop --fg-daemon from argv.
func fakeDaemon(t *testing.T) int {
	t.Helper()
	cmd := exec.Command("sh", "-c", "sleep 30; :", "--fg-daemon")
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	return cmd.Process.Pid
}

// captureStdout runs f with os.Stdout redirected and returns what it printed.
func captureStdout(t *testing.T, f func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	old := os.Stdout
	os.Stdout = w
	done := make(chan string)
	go func() {
		b, _ := io.ReadAll(r)
		done <- string(b)
	}()
	f()
	os.Stdout = old
	_ = w.Close()
	return <-done
}

// emacsclient stub: answers (emacs-pid) with pid, counts 3 file buffers, and
// fails the unsaved-buffer query (form matched first: it also names
// buffer-file-name).
func emacsclientStub(pid int, unsavedOK bool) string {
	unsaved := "exit 1"
	if unsavedOK {
		unsaved = "echo 2"
	}
	return `case "$2" in
  "(emacs-pid)") echo ` + strconv.Itoa(pid) + ` ;;
  *buffer-modified-p*) ` + unsaved + ` ;;
  *buffer-file-name*) echo 3 ;;
  *) echo t ;;
esac`
}

// Regression: with systemctl failing, the managed MainPID is
// unknown. Status must say so, and must NOT call the live daemon an orphan or
// a deadlock -- both lines tell the user to run a destructive reset.
func TestStatusEmacsUnknownServiceNeverReportsOrphan(t *testing.T) {
	pid := fakeDaemon(t)
	fakeBins(t, map[string]string{
		"systemctl":   `echo "Failed to connect to bus" >&2; exit 1`,
		"pgrep":       "echo " + strconv.Itoa(pid),
		"emacsclient": emacsclientStub(pid, true),
	})
	out := captureStdout(t, statusEmacs)

	if !strings.Contains(out, "service: unknown") {
		t.Errorf("status did not report the service as unknown:\n%s", out)
	}
	for _, bad := range []string{"orphan", "deadlock", "emacs-doctor reset"} {
		if strings.Contains(out, bad) {
			t.Errorf("status said %q with the service state unknown:\n%s", bad, out)
		}
	}
	if !strings.Contains(out, strconv.Itoa(pid)) {
		t.Errorf("status did not list the unclassified daemon PID %d:\n%s", pid, out)
	}
}

// The known-state path still reports a real orphan.
func TestStatusEmacsKnownServiceReportsOrphan(t *testing.T) {
	pid := fakeDaemon(t)
	fakeBins(t, map[string]string{
		"systemctl":   `printf 'ActiveState=active\nSubState=running\nMainPID=1\nNRestarts=0\n'`,
		"pgrep":       "echo " + strconv.Itoa(pid),
		"emacsclient": emacsclientStub(pid, true),
	})
	out := captureStdout(t, statusEmacs)
	if !strings.Contains(out, "orphan daemon(s): "+strconv.Itoa(pid)) {
		t.Errorf("status missed a real orphan:\n%s", out)
	}
	if !strings.Contains(out, "unsaved: 2") {
		t.Errorf("status did not print the unsaved count:\n%s", out)
	}
}

// Regression: a failed unsaved-buffer query must print
// "unsaved: unknown", not "unsaved: 0" -- 0 reads as "safe to reset".
func TestStatusEmacsUnsavedUnknown(t *testing.T) {
	pid := fakeDaemon(t)
	fakeBins(t, map[string]string{
		"systemctl":   `printf 'ActiveState=active\nSubState=running\nMainPID=` + strconv.Itoa(pid) + `\nNRestarts=0\n'`,
		"pgrep":       "echo " + strconv.Itoa(pid),
		"emacsclient": emacsclientStub(pid, false),
	})
	out := captureStdout(t, statusEmacs)
	if !strings.Contains(out, "unsaved: unknown") {
		t.Errorf("status did not print unsaved: unknown:\n%s", out)
	}
	if strings.Contains(out, "unsaved: 0") {
		t.Errorf("status printed unsaved: 0 for a failed query:\n%s", out)
	}
}

func TestBufferSummary(t *testing.T) {
	tests := []struct {
		nbuf   int
		nbufOK bool
		nmod   int
		nmodOK bool
		want   string
	}{
		{3, true, 1, true, "open file buffers: 3 (unsaved: 1)"},
		{3, true, 0, false, "open file buffers: 3 (unsaved: unknown)"},
		{0, false, 0, false, "open file buffers: unknown (unsaved: unknown)"},
	}
	for _, tt := range tests {
		if got := bufferSummary(tt.nbuf, tt.nbufOK, tt.nmod, tt.nmodOK); got != tt.want {
			t.Errorf("bufferSummary(%d,%v,%d,%v) = %q, want %q",
				tt.nbuf, tt.nbufOK, tt.nmod, tt.nmodOK, got, tt.want)
		}
	}
}
