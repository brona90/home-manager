// Package shellquote provides POSIX-shell single-quote escaping for strings
// embedded into `sh -c` command lines (tmux run-shell, display-popup, and
// new-window all evaluate their command argument with the shell).
package shellquote

import "strings"

// Quote wraps s in single quotes, escaping embedded single quotes with the
// standard '"'"' dance. Unlike Go's %q, the result is inert to $, backticks,
// globs, and word splitting.
func Quote(s string) string {
	return `'` + strings.ReplaceAll(s, `'`, `'"'"'`) + `'`
}

// QuoteAll quotes every element of items.
func QuoteAll(items []string) []string {
	q := make([]string, len(items))
	for i, s := range items {
		q[i] = Quote(s)
	}
	return q
}
