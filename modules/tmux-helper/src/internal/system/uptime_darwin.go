//go:build darwin

package system

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// Uptime returns time since boot, computed from sysctl kern.boottime. We shell
// out rather than dropping into syscall.Sysctl because the kern.boottime MIB
// returns a packed timeval that's awkward to decode portably; "sysctl -n" hands
// us text we can parse. The cost is one fork per call -- 5 ms range -- which is
// fine at status-interval cadence.
func Uptime() (time.Duration, error) {
	out, err := exec.Command("sysctl", "-n", "kern.boottime").Output()
	if err != nil {
		return 0, fmt.Errorf("sysctl kern.boottime: %w", err)
	}
	return parseDarwinBoottime(string(out), time.Now())
}

func parseDarwinBoottime(out string, now time.Time) (time.Duration, error) {
	// Output: "{ sec = 1745891234, usec = 5678 } Sun Apr 28 ..."
	s := strings.TrimSpace(out)
	idx := strings.Index(s, "sec =")
	if idx < 0 {
		return 0, fmt.Errorf("unrecognized kern.boottime output: %q", out)
	}
	rest := s[idx+len("sec ="):]
	end := strings.IndexAny(rest, ",}")
	if end < 0 {
		return 0, fmt.Errorf("unrecognized kern.boottime output: %q", out)
	}
	secStr := strings.TrimSpace(rest[:end])
	secs, err := strconv.ParseInt(secStr, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parsing kern.boottime sec: %w", err)
	}
	boot := time.Unix(secs, 0)
	if boot.After(now) {
		return 0, fmt.Errorf("boot time %s is in the future", boot)
	}
	return now.Sub(boot), nil
}
