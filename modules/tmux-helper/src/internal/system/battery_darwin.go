//go:build darwin

package system

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// ReadBattery shells out to pmset -g batt and parses the InternalBattery
// line. Desktop Macs print no InternalBattery and we return Present=false.
func ReadBattery() (Battery, error) {
	out, err := exec.Command("pmset", "-g", "batt").Output()
	if err != nil {
		return Battery{}, fmt.Errorf("pmset: %w", err)
	}
	return parsePmsetBatt(string(out))
}

// parsePmsetBatt extracts percent + charging state from pmset -g batt:
//
//	Now drawing from 'Battery Power'
//	 -InternalBattery-0 (id=...)\t87%; discharging; 4:32 remaining present: true
func parsePmsetBatt(s string) (Battery, error) {
	for _, line := range strings.Split(s, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "-InternalBattery") {
			continue
		}
		pctEnd := strings.Index(line, "%")
		if pctEnd <= 0 {
			return Battery{}, nil
		}
		i := pctEnd - 1
		for i >= 0 && line[i] >= '0' && line[i] <= '9' {
			i--
		}
		pct, err := strconv.Atoi(line[i+1 : pctEnd])
		if err != nil {
			return Battery{}, err
		}
		rest := strings.ToLower(line[pctEnd:])
		// pmset wording: "discharging", "charging", "charged", "AC attached"
		charging := strings.Contains(rest, "charging") && !strings.Contains(rest, "discharging")
		charging = charging || strings.Contains(rest, "charged") || strings.Contains(rest, "ac attached")
		return Battery{Present: true, Percent: pct, Charging: charging}, nil
	}
	return Battery{}, nil
}
