package cmds

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"tmux-helper/internal/tmux"
)

func Picker(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: picker <sessions|windows|panes|projects>")
	}
	if _, err := exec.LookPath("fzf"); err != nil {
		return tmux.Run("display-message", "fzf not on PATH (install fzf)")
	}
	switch args[0] {
	case "sessions":
		return pickerSessions()
	case "windows":
		return pickerWindows()
	case "panes":
		return pickerPanes()
	case "projects":
		return pickerProjects()
	default:
		return fmt.Errorf("unknown picker: %s", args[0])
	}
}

func popup(title, listCmd string, action func(string) error) error {
	tmpDir, err := os.MkdirTemp("", "tmux-helper-picker-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir)
	resultPath := filepath.Join(tmpDir, "result")

	popupCmd := fmt.Sprintf(
		"(%s) | fzf --no-mouse --reverse --height=100%% --prompt='%s> ' > %q",
		listCmd, title, resultPath,
	)
	if err := tmux.Run("display-popup", "-E", "-w", "60%", "-h", "60%", "sh", "-c", popupCmd); err != nil {
		return err
	}
	out, err := os.ReadFile(resultPath)
	if err != nil {
		return nil
	}
	chosen := strings.TrimSpace(string(out))
	if chosen == "" {
		return nil
	}
	return action(chosen)
}

func pickerSessions() error {
	return popup("session", "tmux list-sessions -F '#{session_name}'", func(name string) error {
		return tmux.Run("switch-client", "-t", name)
	})
}

func pickerWindows() error {
	return popup("window",
		"tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}'",
		func(line string) error {
			target := strings.Fields(line)[0]
			return tmux.Run("select-window", "-t", target)
		})
}

func pickerPanes() error {
	return popup("pane",
		"tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_title}'",
		func(line string) error {
			target := strings.Fields(line)[0]
			return tmux.Run("select-pane", "-t", target)
		})
}

func pickerProjects() error {
	roots, err := projectRoots()
	if err != nil {
		return tmux.Run("display-message", "no projects found: "+err.Error())
	}
	if len(roots) == 0 {
		return tmux.Run("display-message", "no projects found")
	}
	var labeled []string
	for _, r := range roots {
		labeled = append(labeled, filepath.Base(r)+"\t"+r)
	}
	listCmd := "printf '%s\n' " + strings.Join(quoteAll(labeled), " ")
	return popup("project", listCmd, func(line string) error {
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			return fmt.Errorf("malformed picker line: %q", line)
		}
		name, root := parts[0], parts[1]
		if err := tmux.Run("switch-client", "-t", name); err == nil {
			return nil
		}
		if err := tmux.Run("new-session", "-d", "-s", name, "-c", root); err != nil {
			return err
		}
		return tmux.Run("switch-client", "-t", name)
	})
}

func projectRoots() ([]string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	for _, candidate := range []string{
		filepath.Join(home, ".emacs.d/.local/cache/projectile-bookmarks.eld"),
		filepath.Join(home, ".config/emacs/.local/cache/projectile-bookmarks.eld"),
	} {
		data, err := os.ReadFile(candidate)
		if err != nil {
			continue
		}
		paths := parseProjectileEld(string(data))
		if len(paths) > 0 {
			return paths, nil
		}
	}
	return scanFallbackRoots(home), nil
}

func parseProjectileEld(s string) []string {
	var out []string
	in := false
	start := 0
	for i, c := range s {
		if c != '"' {
			continue
		}
		if !in {
			in = true
			start = i + 1
		} else {
			token := strings.TrimRight(s[start:i], "/")
			if strings.HasPrefix(token, "/") || strings.HasPrefix(token, "~") {
				out = append(out, token)
			}
			in = false
		}
	}
	return out
}

func scanFallbackRoots(home string) []string {
	var out []string
	for _, parent := range []string{
		filepath.Join(home, "projects"),
		filepath.Join(home, "work"),
		filepath.Join(home, "code"),
		filepath.Join(home, ".config"),
	} {
		entries, err := os.ReadDir(parent)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			full := filepath.Join(parent, e.Name())
			for _, marker := range []string{".git", ".mise.toml", "flake.nix"} {
				if _, err := os.Stat(filepath.Join(full, marker)); err == nil {
					out = append(out, full)
					break
				}
			}
		}
	}
	return out
}

func quoteAll(items []string) []string {
	q := make([]string, len(items))
	for i, s := range items {
		q[i] = `'` + strings.ReplaceAll(s, `'`, `'"'"'`) + `'`
	}
	return q
}
