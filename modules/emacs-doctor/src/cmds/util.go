package cmds

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// nrStr renders an NRestarts value, showing "?" when unknown (-1).
func nrStr(n int) string {
	if n < 0 {
		return "?"
	}
	return strconv.Itoa(n)
}

// joinInts formats a slice of PIDs as "100, 200".
func joinInts(xs []int) string {
	parts := make([]string, len(xs))
	for i, x := range xs {
		parts[i] = strconv.Itoa(x)
	}
	return strings.Join(parts, ", ")
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func haveCmd(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}
