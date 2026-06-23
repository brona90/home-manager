// Package sys reports lightweight WSL/system health: load, top CPU consumers,
// memory, and the WSLg graphics path. Parsing helpers are pure for testing.
package sys

import (
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
)

// Cores is the number of logical CPUs.
func Cores() int { return runtime.NumCPU() }

// ParseLoadAvg extracts the 1-minute load and the "1m 5m 15m" triple from the
// contents of /proc/loadavg.
func ParseLoadAvg(s string) (one float64, triple string, ok bool) {
	f := strings.Fields(s)
	if len(f) < 3 {
		return 0, "", false
	}
	v, err := strconv.ParseFloat(f[0], 64)
	if err != nil {
		return 0, "", false
	}
	return v, strings.Join(f[:3], " "), true
}

// LoadAvg reads /proc/loadavg.
func LoadAvg() (one float64, triple string, ok bool) {
	b, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return 0, "", false
	}
	return ParseLoadAvg(string(b))
}

// TopCPU returns up to n lines of `ps` output sorted by CPU (header included).
func TopCPU(n int) []string {
	out, err := exec.Command("ps", "-eo", "pid,pcpu,pmem,comm", "--sort=-pcpu").Output()
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	if len(lines) > n {
		lines = lines[:n]
	}
	return lines
}

// MemSummary returns the header and Mem: row from `free -h`.
func MemSummary() []string {
	out, err := exec.Command("free", "-h").Output()
	if err != nil {
		return nil
	}
	var keep []string
	for i, line := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		if i == 0 || strings.HasPrefix(line, "Mem:") {
			keep = append(keep, line)
		}
	}
	return keep
}

// OllamaCPU returns the summed CPU% of any running ollama processes.
func OllamaCPU() (float64, bool) {
	out, err := exec.Command("ps", "-o", "pcpu=", "-C", "ollama").Output()
	if err != nil {
		return 0, false
	}
	fields := strings.Fields(string(out))
	if len(fields) == 0 {
		return 0, false
	}
	var sum float64
	for _, f := range fields {
		if v, e := strconv.ParseFloat(f, 64); e == nil {
			sum += v
		}
	}
	return sum, true
}

// HasHardwareGL reports whether the Mesa d3d12 driver (WSLg HW GL) is present.
func HasHardwareGL() bool {
	_, err := os.Stat("/usr/lib/x86_64-linux-gnu/dri/d3d12_dri.so")
	return err == nil
}

// GPU queries nvidia-smi (PATH, then the WSL-provided path) for a one-line summary.
func GPU() (string, bool) {
	for _, bin := range []string{"nvidia-smi", "/usr/lib/wsl/lib/nvidia-smi"} {
		out, err := exec.Command(bin,
			"--query-gpu=name,driver_version,utilization.gpu",
			"--format=csv,noheader").Output()
		if err == nil {
			return strings.TrimSpace(string(out)), true
		}
	}
	return "", false
}
