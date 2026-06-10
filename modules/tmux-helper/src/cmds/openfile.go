package cmds

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"tmux-helper/internal/shellquote"
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
	file = expandTilde(file)

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

	// $EDITOR fallback: copy-pipe gives us no tty, and $EDITOR may be a
	// multi-word command line ("emacsclient -t --alternate-editor ..."), so
	// host the editor in a fresh tmux window where the shell parses $EDITOR
	// and the file path is single-quote-escaped against word splitting and
	// metacharacters.
	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = "vi"
	}
	cmdline := editor
	if line > 0 {
		// vi/vim/nvim/emacsclient all accept +LINE before the file.
		cmdline += fmt.Sprintf(" +%d", line)
	}
	cmdline += " " + shellquote.Quote(file)
	return tmux.Run("new-window", cmdline)
}

// expandTilde resolves a leading ~/ (or bare ~) against the current user's
// home directory. Nothing downstream (emacsclient, exec) expands ~ for us.
func expandTilde(path string) string {
	if path != "~" && !strings.HasPrefix(path, "~/") {
		return path
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return path
	}
	return filepath.Join(home, strings.TrimPrefix(path, "~"))
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
