package cmds

import (
	"fmt"
	"os"
	"strings"

	"tmux-helper/internal/theme"
	"tmux-helper/internal/tmux"
)

// Theme dispatches the `theme` subcommand. Three actions:
//   apply <name>  -- emit set-option commands for the named palette
//   cycle         -- pick the next theme in sorted order, apply, store
//   list          -- print available theme names (one per line)
func Theme(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: theme <apply <name> | cycle | list>")
	}
	switch args[0] {
	case "apply":
		if len(args) != 2 {
			return fmt.Errorf("usage: theme apply <name>")
		}
		return themeApply(args[1])
	case "cycle":
		return themeCycle()
	case "list":
		return themeList()
	default:
		return fmt.Errorf("unknown theme subcommand: %s", args[0])
	}
}

const optThemePreset = "@tmux_theme_preset"

func loadThemes() (theme.Themes, error) {
	path := os.Getenv("TMUX_HELPER_THEMES")
	if path == "" {
		return nil, fmt.Errorf("TMUX_HELPER_THEMES not set")
	}
	return theme.Load(path)
}

func helperPath() string {
	p, err := os.Executable()
	if err != nil || p == "" {
		return "tmux-helper"
	}
	return p
}

func themeApply(name string) error {
	themes, err := loadThemes()
	if err != nil {
		return err
	}
	cmds, err := themes.SetCommands(name, helperPath())
	if err != nil {
		return err
	}
	for _, argv := range cmds {
		if err := tmux.Run(argv...); err != nil {
			return fmt.Errorf("apply %q: %w", argv[0], err)
		}
	}
	if err := tmux.SetGlobalOption(optThemePreset, name); err != nil {
		return err
	}
	return tmux.Run("display-message", "theme: "+name)
}

func themeCycle() error {
	themes, err := loadThemes()
	if err != nil {
		return err
	}
	current := strings.TrimSpace(maybeOpt(optThemePreset))
	next := themes.Next(current)
	return themeApply(next)
}

func themeList() error {
	themes, err := loadThemes()
	if err != nil {
		return err
	}
	for _, n := range themes.Names() {
		fmt.Println(n)
	}
	return nil
}
