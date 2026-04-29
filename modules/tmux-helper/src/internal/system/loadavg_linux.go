//go:build linux

package system

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// LoadAvg reads /proc/loadavg and returns the 1/5/15-minute averages.
func LoadAvg() ([3]float64, error) {
	data, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return [3]float64{}, err
	}
	return parseProcLoadavg(string(data))
}

func parseProcLoadavg(s string) ([3]float64, error) {
	fields := strings.Fields(s)
	if len(fields) < 3 {
		return [3]float64{}, fmt.Errorf("malformed /proc/loadavg: %q", s)
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
