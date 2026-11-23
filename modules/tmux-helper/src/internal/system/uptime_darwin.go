//go:build darwin

package system

import (
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// uptimeTimeout bounds the sysctl call like every other status-path exec
// (ReadBattery's pmset, the ps calls): Uptime runs on every status-interval
// refresh, so an unbounded hang would pile up a stuck helper per tick. A var
// so tests can shrink it.
var uptimeTimeout = ExecTimeout

// sysctlCommand builds the sysctl invocation. A var so tests can substitute
// a fake sysctl that hangs.
var sysctlCommand = func(ctx context.Context, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, "sysctl", args...)
}

// Uptime returns time since boot, computed from sysctl kern.boottime. We shell
// out rather than dropping into syscall.Sysctl because the kern.boottime MIB
// returns a packed timeval that's awkward to decode portably; "sysctl -n" hands
// us text we can parse. The cost is one fork per call -- 5 ms range -- which is
// fine at status-interval cadence.
func Uptime() (time.Duration, error) {
	ctx, cancel := context.WithTimeout(context.Background(), uptimeTimeout)
	defer cancel()
	out, err := sysctlCommand(ctx, "-n", "kern.boottime").Output()
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
