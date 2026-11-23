// Package clipboard selects an OS clipboard backend at runtime and pipes
// stdin into it. Selection rules match common conventions: darwin -> pbcopy;
// WSL -> clip.exe; Wayland -> wl-copy; X11 -> xclip then xsel.
package clipboard

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"runtime"
	"time"
	"unicode/utf16"
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
	// clip.exe interprets plain input in the OEM codepage, mangling any
	// non-ASCII UTF-8. It handles BOM-prefixed UTF-16LE correctly, so
	// transcode before piping (dependency-free: stdlib unicode/utf16).
	if b.Name == "clip.exe" {
		data, err := io.ReadAll(r)
		if err != nil {
			return err
		}
		r = bytes.NewReader(encodeUTF16LEBOM(data))
	}
	return runBackend(b, r)
}

// copyTimeout bounds the clipboard tool. Every backend returns as soon as it
// has taken its stdin (wl-copy and xclip fork a background process to own
// the selection, and the one we started exits), so only a wedged tool --
// most plausibly clip.exe across a stalled WSL interop bridge -- reaches
// it. Generous because interop alone can add seconds, and the copy-pipe job
// this runs as never blocks the user anyway. A var so tests can shrink it.
var copyTimeout = 10 * time.Second

// runBackend pipes r into the backend's argv, bounded by copyTimeout.
func runBackend(b *Backend, r io.Reader) error {
	ctx, cancel := context.WithTimeout(context.Background(), copyTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, b.Argv[0], b.Argv[1:]...)
	cmd.Stdin = r
	cmd.Stderr = os.Stderr
	// When r is not an *os.File (the clip.exe UTF-16 path), exec feeds it
	// through a pipe from a goroutine that Wait also waits for. A killed
	// child whose descendant still holds the pipe would stall that forever;
	// WaitDelay caps it.
	cmd.WaitDelay = time.Second
	err := cmd.Run()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return fmt.Errorf("%s: timed out after %v: %w", b.Name, copyTimeout, err)
	}
	return err
}

// encodeUTF16LEBOM converts UTF-8 bytes to UTF-16LE with a leading BOM.
// Invalid UTF-8 sequences become U+FFFD, matching Go's rune decoding.
func encodeUTF16LEBOM(data []byte) []byte {
	units := utf16.Encode([]rune(string(data)))
	out := make([]byte, 0, 2*len(units)+2)
	out = append(out, 0xFF, 0xFE) // UTF-16LE BOM
	for _, u := range units {
		out = append(out, byte(u), byte(u>>8))
	}
	return out
}
