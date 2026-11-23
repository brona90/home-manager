package tmux

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// cmdTimeout bounds Run and Output/OutputTrim so a hung tmux server can't
// freeze the status bar or wedge a key binding: every one of those calls
// (set-option, display-message, switch-client, select-pane, new-window, ...)
// returns as soon as the server has processed it. Only RunInteractive is
// unbounded, because display-popup -E blocks until the user closes the popup.
// A var rather than a const so tests can shrink it.
var cmdTimeout = 2 * time.Second

// tmuxCommand builds the exec.Cmd for one tmux invocation. A var so tests can
// substitute a fake tmux that hangs.
var tmuxCommand = func(ctx context.Context, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, "tmux", args...)
}

// Run executes "tmux <args...>", killing it after cmdTimeout. Use it for
// every command that does not wait on the user.
func Run(args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), cmdTimeout)
	defer cancel()
	return describe(ctx, args, tmuxCommand(ctx, args...).Run())
}

// RunInteractive executes "tmux <args...>" with no time bound. Only for
// commands that block until the user finishes with them -- today that is
// display-popup -E alone. Anything else belongs in Run.
func RunInteractive(args ...string) error {
	return describe(context.Background(), args, tmuxCommand(context.Background(), args...).Run())
}

// Output executes "tmux <args...>" and returns stdout, bounded like Run.
func Output(args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), cmdTimeout)
	defer cancel()
	out, err := tmuxCommand(ctx, args...).Output()
	return out, describe(ctx, args, err)
}

// describe turns an exec error into one that names the tmux command, says
// plainly when the bound killed it (a bare "signal: killed" reads like a
// crash), and carries tmux's stderr when Output captured it.
func describe(ctx context.Context, args []string, err error) error {
	if err == nil {
		return nil
	}
	cmdline := strings.Join(args, " ")
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return fmt.Errorf("tmux %s: timed out after %v: %w", cmdline, cmdTimeout, err)
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) && len(ee.Stderr) > 0 {
		return fmt.Errorf("tmux %s: %w: %s", cmdline, err, bytes.TrimSpace(ee.Stderr))
	}
	return fmt.Errorf("tmux %s: %w", cmdline, err)
}

// OutputTrim is Output with a trailing newline stripped, returning a string.
func OutputTrim(args ...string) (string, error) {
	out, err := Output(args...)
	if err != nil {
		return "", err
	}
	return strings.TrimRight(string(out), "\n"), nil
}
