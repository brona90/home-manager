// Package clipboard selects an OS clipboard backend at runtime and pipes
// stdin into it. Selection rules match common conventions: darwin -> pbcopy;
// WSL -> clip.exe; Wayland -> wl-copy; X11 -> xclip then xsel.
package clipboard

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"runtime"
)

// ErrNoBackend means no usable clipboard tool was found on PATH for the
// current platform/session.
var ErrNoBackend = errors.New("no clipboard backend available")

// Backend describes the selected tool: a short name and the argv (command
// plus initial flags). Clipboard contents are written to the command's stdin.
type Backend struct {
	Name string
	Argv []string
}

// LookPathFunc and GetenvFunc are injection points for testing.
type LookPathFunc func(file string) (string, error)
type GetenvFunc func(key string) string

// Detect returns the preferred backend given goos, a PATH lookup, and an env
// reader. Callers in production use DefaultDetect.
func Detect(goos string, lookPath LookPathFunc, getenv GetenvFunc) (*Backend, error) {
	if lookPath == nil {
		lookPath = exec.LookPath
	}
	if getenv == nil {
		getenv = os.Getenv
	}

	switch goos {
	case "darwin":
		if p, err := lookPath("pbcopy"); err == nil {
			return &Backend{Name: "pbcopy", Argv: []string{p}}, nil
		}
		return nil, fmt.Errorf("%w: pbcopy not found on darwin", ErrNoBackend)

	case "linux":
		// WSL takes priority when present so users get the native Windows
		// clipboard rather than the (often-empty) Linux X server.
		if isWSL(getenv) {
			if p, err := lookPath("clip.exe"); err == nil {
				return &Backend{Name: "clip.exe", Argv: []string{p}}, nil
			}
		}
		if getenv("WAYLAND_DISPLAY") != "" {
			if p, err := lookPath("wl-copy"); err == nil {
				return &Backend{Name: "wl-copy", Argv: []string{p}}, nil
			}
		}
		if getenv("DISPLAY") != "" {
			if p, err := lookPath("xclip"); err == nil {
				return &Backend{Name: "xclip", Argv: []string{p, "-selection", "clipboard"}}, nil
			}
			if p, err := lookPath("xsel"); err == nil {
				return &Backend{Name: "xsel", Argv: []string{p, "--clipboard", "--input"}}, nil
			}
		}
		// Last-resort fallback: clip.exe even without WSL_DISTRO_NAME, in case
		// detection misses (PATH includes /mnt/c/Windows/System32 in WSL1).
		if p, err := lookPath("clip.exe"); err == nil {
			return &Backend{Name: "clip.exe", Argv: []string{p}}, nil
		}
		return nil, fmt.Errorf("%w: no usable backend (WAYLAND_DISPLAY=%q DISPLAY=%q)",
			ErrNoBackend, getenv("WAYLAND_DISPLAY"), getenv("DISPLAY"))

	default:
		return nil, fmt.Errorf("%w: unsupported goos %s", ErrNoBackend, goos)
	}
}

// isWSL detects WSL via env vars set by /init at session start. We don't read
// /proc/version because WSL1 reports the Linux kernel version unmodified.
func isWSL(getenv GetenvFunc) bool {
	return getenv("WSL_DISTRO_NAME") != "" || getenv("WSL_INTEROP") != ""
}

// DefaultDetect picks a backend for the running process.
func DefaultDetect() (*Backend, error) {
	return Detect(runtime.GOOS, exec.LookPath, os.Getenv)
}

// Copy writes the contents of r to the detected clipboard backend.
func Copy(r io.Reader) error {
	b, err := DefaultDetect()
	if err != nil {
		return err
	}
	cmd := exec.Command(b.Argv[0], b.Argv[1:]...)
	cmd.Stdin = r
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
