package cmds

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

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

	opened, err := openInEmacs(args)
	if err != nil {
		// No fallback on timeout: the daemon may still act on the request,
		// and a second editor on the same file is worse than a message.
		// The text is fixed, not err.Error(): display-message format-expands
		// its argument, and err would carry the selected path.
		_ = tmux.Run("display-message", "open-file: emacsclient timed out; Emacs daemon busy or hung?")
		return err
	}
	if opened {
		return nil
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

// emacsclientTimeout bounds the emacsclient -n call. -n returns as soon as
// the server has visited the file, so this is only ever reached by a daemon
// that is wedged (a blocking prompt, a hung TRAMP connection, a stuck
// process filter). Unbounded, that left this process -- and the copy-pipe job
// tmux runs it as -- alive until the daemon recovered or was killed. Generous
// because visiting a large file legitimately takes a moment.
// A var so tests can shrink it.
var emacsclientTimeout = 10 * time.Second

// emacsclientCommand builds the emacsclient invocation. A var so tests can
// substitute a fake emacsclient that hangs.
var emacsclientCommand = func(ctx context.Context, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, "emacsclient", args...)
}

// openInEmacs runs `emacsclient <args>` with a time bound. opened reports
// whether the daemon took the file. A non-nil error means the bound fired and
// the caller must not fall back to $EDITOR; any other failure (emacsclient
// not installed, no daemon running) returns opened=false, err=nil, and the
// caller falls back as before.
func openInEmacs(args []string) (opened bool, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), emacsclientTimeout)
	defer cancel()
	cmd := emacsclientCommand(ctx, args...)
	cmd.Stderr = os.Stderr
	runErr := cmd.Run()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return false, fmt.Errorf("emacsclient %s: timed out after %v: %w", strings.Join(args, " "), emacsclientTimeout, runErr)
	}
	return runErr == nil, nil
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
