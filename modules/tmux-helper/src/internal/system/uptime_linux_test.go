//go:build linux

package system

import (
	"testing"
	"time"
)

func TestParseProcUptime(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		want    time.Duration
		wantErr bool
	}{
		{"two fields", "12345.67 5432.10\n", time.Duration(12345.67 * float64(time.Second)), false},
		{"single field no newline", "100.5", 100*time.Second + 500*time.Millisecond, false},
		{"zero", "0.00 0.00\n", 0, false},
		{"sub-second", "0.42\n", 420 * time.Millisecond, false},
		{"empty", "", 0, true},
		{"whitespace only", "   \n", 0, true},
		{"non-numeric", "abc def\n", 0, true},
		{"negative", "-5.0 0.0\n", 0, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseProcUptime(tt.in)
			if (err != nil) != tt.wantErr {
				t.Errorf("err = %v, wantErr = %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && got != tt.want {
				t.Errorf("got %v, want %v", got, tt.want)
			}
		})
	}
}
