//go:build linux

package system

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// ReadBattery reads the first /sys/class/power_supply/BAT* entry. WSL,
// desktops, and headless servers have no BAT* directory and Present comes
// back false; callers render nothing in that case.
func ReadBattery() (Battery, error) {
	matches, err := filepath.Glob("/sys/class/power_supply/BAT*")
	if err != nil || len(matches) == 0 {
		return Battery{}, nil
	}
	dir := matches[0]
	pctRaw, err := os.ReadFile(filepath.Join(dir, "capacity"))
	if err != nil {
		return Battery{}, err
	}
	pct, err := strconv.Atoi(strings.TrimSpace(string(pctRaw)))
	if err != nil {
		return Battery{}, err
	}
	statusRaw, _ := os.ReadFile(filepath.Join(dir, "status"))
	st := strings.TrimSpace(string(statusRaw))
	// "Full" reads as charging so the icon flips to plug, not battery.
	charging := st == "Charging" || st == "Full"
	return Battery{Present: true, Percent: pct, Charging: charging}, nil
}
