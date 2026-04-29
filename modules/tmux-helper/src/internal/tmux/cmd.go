package tmux

import (
	"bytes"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

// Run executes "tmux <args...>".
func Run(args ...string) error {
	return exec.Command("tmux", args...).Run()
}

// Output executes "tmux <args...>" and returns stdout.
func Output(args ...string) ([]byte, error) {
	out, err := exec.Command("tmux", args...).Output()
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
