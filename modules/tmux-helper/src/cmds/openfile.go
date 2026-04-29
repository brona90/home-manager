package cmds

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"tmux-helper/internal/tmux"
)

// OpenFile reads piped selection text from stdin, parses a file path and
// optional line/col, and opens it in the running emacs daemon via
// emacsclient. Falls back to $EDITOR if no daemon. Bound to copy-mode-vi
// `o` so users can select text that contains a path (compiler errors,
// stack traces, ripgrep results, etc.) and jump straight to it.
//
// Recognized patterns (first match wins):
//   path:LINE:COL   -> emacsclient -n +LINE:COL path
//   path:LINE       -> emacsclient -n +LINE path
//   path            -> emacsclient -n path
func OpenFile(_ []string) error {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		return err
	}
	text := strings.TrimSpace(string(data))

	file, line, col, ok := parseFileRef(text)
	if !ok {
		return tmux.Run("display-message", "open-file: no path found in selection")
	}

	args := []string{"-n"}
	if line > 0 {
		if col > 0 {
			args = append(args, fmt.Sprintf("+%d:%d", line, col))
		} else {
			args = append(args, fmt.Sprintf("+%d", line))
		}
	}
	args = append(args, file)

	if _, err := exec.LookPath("emacsclient"); err == nil {
		cmd := exec.Command("emacsclient", args...)
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err == nil {
			return nil
		}
		// emacsclient ran but errored (no daemon, etc.) -- fall through to
		// the $EDITOR fallback rather than just bailing.
	}

	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = "vi"
	}
	cmd := exec.Command(editor, file)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

// fileRefRe matches a path-like token followed by optional :line[:col].
// We require the path to contain a `/` or end with a typical extension --
// otherwise common selections like "10:30" (a time) would match.
var fileRefRe = regexp.MustCompile(`([\w./~][\w./~+\-]*\.\w+|[\w./~+\-]+/[\w./~+\-]+)(?::(\d+))?(?::(\d+))?`)

func parseFileRef(text string) (file string, line, col int, ok bool) {
	m := fileRefRe.FindStringSubmatch(text)
	if m == nil {
		return "", 0, 0, false
	}
	file = m[1]
	if m[2] != "" {
		fmt.Sscanf(m[2], "%d", &line)
	}
	if m[3] != "" {
		fmt.Sscanf(m[3], "%d", &col)
	}
	return file, line, col, true
}
