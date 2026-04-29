//go:build darwin

package system

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// LoadAvg returns 1/5/15-minute averages from sysctl vm.loadavg. The MIB returns
// scaled fixed-point integers; "sysctl -n" already converts and prints them as
// decimal floats, so we just parse the formatted output.
func LoadAvg() ([3]float64, error) {
	out, err := exec.Command("sysctl", "-n", "vm.loadavg").Output()
	if err != nil {
		return [3]float64{}, fmt.Errorf("sysctl vm.loadavg: %w", err)
	}
	return parseDarwinLoadavg(string(out))
}

func parseDarwinLoadavg(s string) ([3]float64, error) {
	// "{ 1.23 4.56 7.89 }\n"
	clean := strings.NewReplacer("{", "", "}", "").Replace(s)
	fields := strings.Fields(clean)
	if len(fields) < 3 {
		return [3]float64{}, fmt.Errorf("malformed vm.loadavg: %q", s)
	}
	var out [3]float64
	for i := 0; i < 3; i++ {
		v, err := strconv.ParseFloat(fields[i], 64)
		if err != nil {
			return [3]float64{}, fmt.Errorf("parsing field %d %q: %w", i, fields[i], err)
		}
		out[i] = v
	}
	return out, nil
}
