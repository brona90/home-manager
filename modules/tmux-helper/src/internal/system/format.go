package system

import (
	"fmt"
	"time"
)

// FormatUptimeShort renders a duration as a compact two-unit string for the
// tmux status bar: "<1m", "Nm", "NhMm", "NdMh", "NyDd". Lower units are
// dropped, not rounded, so "1d 23h 59m" reports as "1d 23h".
func FormatUptimeShort(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	totalMin := int64(d / time.Minute)
	if totalMin < 1 {
		return "<1m"
	}
	totalHour := totalMin / 60
	totalDay := totalHour / 24
	totalYear := totalDay / 365
	switch {
	case totalYear >= 1:
		return fmt.Sprintf("%dy %dd", totalYear, totalDay%365)
	case totalDay >= 1:
		return fmt.Sprintf("%dd %dh", totalDay, totalHour%24)
	case totalHour >= 1:
		return fmt.Sprintf("%dh %dm", totalHour, totalMin%60)
	default:
		return fmt.Sprintf("%dm", totalMin)
	}
}
