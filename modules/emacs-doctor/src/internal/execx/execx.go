// Package execx is the one place emacs-doctor runs an external command and
// waits for its output. Every such call is bounded by a timeout: this tool is
// what you reach for when the daemon or the system is wedged, so it must not
// hang on the very thing it is diagnosing (a busy emacsclient, a stuck user
// bus, a slow nvidia-smi).
package execx

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"syscall"
	"time"
)

// Budgets. Default covers the quick queries (systemctl show, pgrep, ps, free,
// emacsclient -e, xwininfo). GPU is longer because nvidia-smi under WSL
// initialises the driver on first call and routinely takes seconds.
const (
	Default = 2 * time.Second
	GPU     = 10 * time.Second
)

// ErrTimeout is wrapped into the error Run returns when the budget ran out.
var ErrTimeout = errors.New("timed out")

// Run executes name with args and returns its stdout, killing it once timeout
// elapses. A non-zero exit surfaces as a non-nil error (as with
// exec.Cmd.Output); an expired budget surfaces as an error wrapping ErrTimeout.
func Run(timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	// CommandContext alone does NOT bound this call. It kills only the direct
	// child; any process that child forked still holds the stdout pipe, and
	// Output() waits for EOF on it. Measured: `sh -c "sleep 30"` with a 100ms
	// budget returned after 30s. So the child gets its own process group and
	// the whole group is killed, and WaitDelay caps the wait for the pipe in
	// case something escaped the group anyway.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	cmd.WaitDelay = 500 * time.Millisecond
	out, err := cmd.Output()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return string(out), fmt.Errorf("%s: %w after %v", name, ErrTimeout, timeout)
	}
	return string(out), err
}
