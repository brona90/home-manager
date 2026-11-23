package cmds

import (
	"context"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

// TestHelperProcess is not a test: it is the fake `emacsclient` the tests
// below exec, re-entering this test binary (the standard os/exec
// helper-process pattern). It sleeps for FAKE_EMACSCLIENT_SLEEP, then exits
// with FAKE_EMACSCLIENT_EXIT, so the timeout path kills a real child.
func TestHelperProcess(t *testing.T) {
	if os.Getenv("FAKE_EMACSCLIENT") != "1" {
		return
	}
	d, err := time.ParseDuration(os.Getenv("FAKE_EMACSCLIENT_SLEEP"))
	if err != nil {
		os.Exit(2)
	}
	code, err := strconv.Atoi(os.Getenv("FAKE_EMACSCLIENT_EXIT"))
	if err != nil {
		os.Exit(2)
	}
	time.Sleep(d)
	os.Exit(code)
}

// useFakeEmacsclient points emacsclientCommand at TestHelperProcess and
// shrinks emacsclientTimeout to bound, restoring both when the test ends.
func useFakeEmacsclient(t *testing.T, sleep time.Duration, exit int, bound time.Duration) {
	t.Helper()
	origCmd, origTimeout := emacsclientCommand, emacsclientTimeout
	t.Cleanup(func() { emacsclientCommand, emacsclientTimeout = origCmd, origTimeout })
	emacsclientTimeout = bound
	emacsclientCommand = func(ctx context.Context, args ...string) *exec.Cmd {
		cmd := exec.CommandContext(ctx, os.Args[0],
			append([]string{"-test.run=^TestHelperProcess$", "--"}, args...)...)
		cmd.Env = append(os.Environ(), "FAKE_EMACSCLIENT=1",
			"FAKE_EMACSCLIENT_SLEEP="+sleep.String(), "FAKE_EMACSCLIENT_EXIT="+strconv.Itoa(exit))
		return cmd
	}
}

func TestOpenInEmacsIsBounded(t *testing.T) {
	useFakeEmacsclient(t, 10*time.Second, 0, 100*time.Millisecond)
	start := time.Now()
	opened, err := openInEmacs([]string{"-n", "main.go"})
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("openInEmacs took %v against a hung daemon; the bound is not applied", elapsed)
	}
	// err, not opened=false: a timeout must stop the caller falling back to
	// $EDITOR, because the daemon may still open the file.
	if err == nil {
		t.Fatalf("openInEmacs against a hung daemon returned opened=%v, err=nil; want a timeout error", opened)
	}
	if opened {
		t.Error("openInEmacs reported opened=true after a timeout")
	}
	if !strings.Contains(err.Error(), "timed out") {
		t.Errorf("error %q should say it timed out", err)
	}
}

func TestOpenInEmacsSuccess(t *testing.T) {
	useFakeEmacsclient(t, 0, 0, 5*time.Second)
	if opened, err := openInEmacs([]string{"-n", "main.go"}); !opened || err != nil {
		t.Fatalf("openInEmacs = (%v, %v), want (true, nil)", opened, err)
	}
}

// emacsclient exiting non-zero (no daemon) is the $EDITOR-fallback case,
// not an error.
func TestOpenInEmacsNoDaemonFallsBack(t *testing.T) {
	useFakeEmacsclient(t, 0, 1, 5*time.Second)
	if opened, err := openInEmacs([]string{"-n", "main.go"}); opened || err != nil {
		t.Fatalf("openInEmacs = (%v, %v), want (false, nil)", opened, err)
	}
}

func TestOpenInEmacsNotInstalledFallsBack(t *testing.T) {
	orig := emacsclientCommand
	t.Cleanup(func() { emacsclientCommand = orig })
	emacsclientCommand = func(ctx context.Context, args ...string) *exec.Cmd {
		return exec.CommandContext(ctx, "/nonexistent/emacsclient", args...)
	}
	if opened, err := openInEmacs([]string{"-n", "main.go"}); opened || err != nil {
		t.Fatalf("openInEmacs = (%v, %v), want (false, nil)", opened, err)
	}
}

func TestParseFileRef(t *testing.T) {
	tests := []struct {
		name              string
		in                string
		wantFile          string
		wantLine, wantCol int
		wantOK            bool
	}{
		{"go file with line+col", "main.go:42:5", "main.go", 42, 5, true},
		{"go file with line", "main.go:42", "main.go", 42, 0, true},
		{"plain path", "src/foo.go", "src/foo.go", 0, 0, true},
		{"absolute path", "/etc/hosts", "/etc/hosts", 0, 0, true},
		{"compiler error", "Error in foo.go:11:14: missing return", "foo.go", 11, 14, true},
		{"home path", "~/.config/foo.toml:7", "~/.config/foo.toml", 7, 0, true},
		{"no file", "10:30 PM", "", 0, 0, false},
		{"empty", "", "", 0, 0, false},
		{"plain word", "hello world", "", 0, 0, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f, l, c, ok := parseFileRef(tt.in)
			if ok != tt.wantOK {
				t.Errorf("ok=%v want %v", ok, tt.wantOK)
			}
			if !ok {
				return
			}
			if f != tt.wantFile || l != tt.wantLine || c != tt.wantCol {
				t.Errorf("got (%q, %d, %d) want (%q, %d, %d)", f, l, c, tt.wantFile, tt.wantLine, tt.wantCol)
			}
		})
	}
}
