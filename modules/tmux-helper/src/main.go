package main

import (
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"

	"tmux-helper/cmds"
)

// version is set at build time via -ldflags -X main.version=...
var version = "dev"

var errNotImpl = errors.New("not implemented")

type subcommandFunc func(args []string) error

// subcommands lists every subcommand the helper will eventually support.
// Phase 1 only implements 'version'; everything else stubs to errNotImpl.
// Subsequent phases replace stub entries with real implementations in cmds/*.go.
var subcommands = map[string]subcommandFunc{
	"version":         cmdVersion,
	"status":          cmds.Status,
	"clipboard":       cmds.Clipboard,
	"maximize-pane":   cmds.MaximizePane,
	"toggle-mouse":    cmds.ToggleMouse,
	"reload":          cmds.Reload,
	"clear-history":   cmds.ClearHistory,
	"fpp":             cmdStub,
	"urlview":         cmdStub,
	"urlscan":         cmdStub,
	"new-window-ssh":  cmdStub,
	"split-window-ssh": cmdStub,
	"apply-theme":     cmdStub,
	"theme":           cmds.Theme,
	"picker":          cmdStub,
	"navigate":        cmds.Navigate,
	"jump":            cmdStub,
	"open-file":       cmdStub,
}

func main() {
	if len(os.Args) < 2 {
		usage(os.Stderr)
		os.Exit(2)
	}
	name := os.Args[1]
	args := os.Args[2:]

	fn, ok := subcommands[name]
	if !ok {
		fmt.Fprintf(os.Stderr, "tmux-helper: unknown subcommand %q\n", name)
		usage(os.Stderr)
		os.Exit(2)
	}

	if err := fn(args); err != nil {
		fmt.Fprintf(os.Stderr, "tmux-helper %s: %v\n", name, err)
		os.Exit(1)
	}
}

func usage(w *os.File) {
	names := make([]string, 0, len(subcommands))
	for n := range subcommands {
		names = append(names, n)
	}
	sort.Strings(names)
	fmt.Fprintln(w, "usage: tmux-helper <subcommand> [args...]")
	fmt.Fprintln(w, "subcommands:")
	fmt.Fprintln(w, "  "+strings.Join(names, ", "))
}

func cmdVersion(_ []string) error {
	fmt.Println(version)
	return nil
}

func cmdStub(_ []string) error {
	return errNotImpl
}
