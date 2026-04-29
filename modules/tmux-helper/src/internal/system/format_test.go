package system

import (
	"testing"
	"time"
)

func TestFormatUptimeShort(t *testing.T) {
	tests := []struct {
		name string
		in   time.Duration
		want string
	}{
		{"negative", -time.Hour, "<1m"},
		{"zero", 0, "<1m"},
		{"30s", 30 * time.Second, "<1m"},
		{"59s", 59 * time.Second, "<1m"},
		{"1m exact", time.Minute, "1m"},
		{"45m", 45 * time.Minute, "45m"},
		{"59m59s", 59*time.Minute + 59*time.Second, "59m"},
		{"1h 0m", time.Hour, "1h 0m"},
		{"1h 5m", time.Hour + 5*time.Minute, "1h 5m"},
		{"23h 59m", 23*time.Hour + 59*time.Minute, "23h 59m"},
		{"1d 0h", 24 * time.Hour, "1d 0h"},
		{"3d 12h", 3*24*time.Hour + 12*time.Hour, "3d 12h"},
		{"364d 23h", 364*24*time.Hour + 23*time.Hour, "364d 23h"},
		{"1y exact", 365 * 24 * time.Hour, "1y 0d"},
		{"2y 100d", 2*365*24*time.Hour + 100*24*time.Hour, "2y 100d"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := FormatUptimeShort(tt.in); got != tt.want {
				t.Errorf("FormatUptimeShort(%v) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}
