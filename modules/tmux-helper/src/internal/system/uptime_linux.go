//go:build linux

package system

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Uptime reads /proc/uptime and returns how long the system has been up.
func Uptime() (time.Duration, error) {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0, err
	}
	return parseProcUptime(string(data))
}

func parseProcUptime(s string) (time.Duration, error) {
	fields := strings.Fields(s)
	if len(fields) == 0 {
		return 0, fmt.Errorf("empty /proc/uptime")
	}
	secs, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, fmt.Errorf("parsing /proc/uptime seconds: %w", err)
	}
	if secs < 0 {
		return 0, fmt.Errorf("negative uptime: %g", secs)
	}
	return time.Duration(secs * float64(time.Second)), nil
}
