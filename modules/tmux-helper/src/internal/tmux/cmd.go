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

// outputTimeout bounds Output/OutputTrim (introspection queries used on the
// status path) so a hung tmux server can't freeze the status bar. Run is NOT
// bounded: it hosts interactive commands (display-popup -E blocks until the
// user closes the popup).
const outputTimeout = 2 * time.Second

// Run executes "tmux <args...>".
func Run(args ...string) error {
	return exec.Command("tmux", args...).Run()
}

// Output executes "tmux <args...>" and returns stdout.
func Output(args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), outputTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "tmux", args...).Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return out, fmt.Errorf("tmux %s: %w: %s", strings.Join(args, " "), err, bytes.TrimSpace(ee.Stderr))
		}
		return out, err
	}
	return out, nil
}

// OutputTrim is Output with a trailing newline stripped, returning a string.
func OutputTrim(args ...string) (string, error) {
	out, err := Output(args...)
	if err != nil {
		return "", err
	}
	return strings.TrimRight(string(out), "\n"), nil
}
