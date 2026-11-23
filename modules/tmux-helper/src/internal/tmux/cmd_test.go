package tmux

import (
	"context"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// TestHelperProcess is not a test: it is the fake `tmux` the tests below
// exec, re-entering this test binary (the standard os/exec helper-process
// pattern). It sleeps for FAKE_TMUX_SLEEP, then exits 0. Running it as a
// real binary means the timeout path exercises an actual child process
// being killed, not a mocked error.
func TestHelperProcess(t *testing.T) {
	if os.Getenv("FAKE_TMUX") != "1" {
		return
	}
	d, err := time.ParseDuration(os.Getenv("FAKE_TMUX_SLEEP"))
	if err != nil {
		os.Exit(2)
	}
	time.Sleep(d)
	os.Exit(0)
}

// useFakeTmux points tmuxCommand at TestHelperProcess sleeping for sleep, and
// shrinks cmdTimeout to bound, restoring both when the test ends.
func useFakeTmux(t *testing.T, sleep, bound time.Duration) {
	t.Helper()
	origCmd, origTimeout := tmuxCommand, cmdTimeout
	t.Cleanup(func() { tmuxCommand, cmdTimeout = origCmd, origTimeout })
	cmdTimeout = bound
	tmuxCommand = func(ctx context.Context, args ...string) *exec.Cmd {
		cmd := exec.CommandContext(ctx, os.Args[0],
			append([]string{"-test.run=^TestHelperProcess$", "--"}, args...)...)
		cmd.Env = append(os.Environ(), "FAKE_TMUX=1", "FAKE_TMUX_SLEEP="+sleep.String())
		return cmd
	}
}

func TestRunIsBounded(t *testing.T) {
	useFakeTmux(t, 10*time.Second, 100*time.Millisecond)
	start := time.Now()
	err := Run("display-message", "hello")
	elapsed := time.Since(start)
	if err == nil {
		t.Fatal("Run against a hung tmux returned nil; want a timeout error")
	}
	if elapsed > 5*time.Second {
		t.Fatalf("Run took %v against a hung tmux; the bound is not applied", elapsed)
	}
	if !strings.Contains(err.Error(), "display-message") || !strings.Contains(err.Error(), "timed out") {
		t.Errorf("error %q should name the command and say it timed out", err)
	}
}

func TestRunSucceedsWithinBound(t *testing.T) {
	useFakeTmux(t, 0, 5*time.Second)
	if err := Run("set-option", "-g", "@x", "y"); err != nil {
		t.Fatalf("Run: %v", err)
	}
}

func TestRunInteractiveIsNotBounded(t *testing.T) {
	// The child outlives cmdTimeout several times over, as a popup the user
	// is still looking at does; RunInteractive must wait for it.
	useFakeTmux(t, 600*time.Millisecond, 50*time.Millisecond)
	if err := RunInteractive("display-popup", "-E", "true"); err != nil {
		t.Fatalf("RunInteractive killed a long-running interactive command: %v", err)
	}
}

func TestOutputIsBounded(t *testing.T) {
	useFakeTmux(t, 10*time.Second, 100*time.Millisecond)
	start := time.Now()
	if _, err := Output("display-message", "-p", "#{pid}"); err == nil {
		t.Fatal("Output against a hung tmux returned nil; want a timeout error")
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("Output took %v against a hung tmux", elapsed)
	}
}
