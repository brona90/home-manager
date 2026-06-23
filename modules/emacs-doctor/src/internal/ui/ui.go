// Package ui provides small colorized status-line helpers. Color is emitted
// only when stdout is a terminal and NO_COLOR is unset.
package ui

import (
	"fmt"
	"os"
)

const (
	cReset = "\033[0m"
	cBold  = "\033[1m"
	cDim   = "\033[2m"
	cRed   = "\033[31m"
	cGreen = "\033[32m"
	cYel   = "\033[33m"
)

var colorize = detectColor()

func detectColor() bool {
	if os.Getenv("NO_COLOR") != "" {
		return false
	}
	fi, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return fi.Mode()&os.ModeCharDevice != 0
}

func paint(code, s string) string {
	if !colorize {
		return s
	}
	return code + s + cReset
}

// Header prints a bold section header preceded by a blank line.
func Header(s string) { fmt.Printf("\n%s\n", paint(cBold, "== "+s+" ==")) }

// OK / Warn / Bad print an indented status line with a colored marker.
func OK(s string)   { fmt.Printf("  %s %s\n", paint(cGreen, "✓"), s) }
func Warn(s string) { fmt.Printf("  %s %s\n", paint(cYel, "⚠"), s) }
func Bad(s string)  { fmt.Printf("  %s %s\n", paint(cRed, "✗"), s) }

// Info prints an indented plain detail line.
func Info(s string) { fmt.Printf("    %s\n", s) }

// Dim returns the string wrapped in the dim SGR (when color is enabled).
func Dim(s string) string { return paint(cDim, s) }
