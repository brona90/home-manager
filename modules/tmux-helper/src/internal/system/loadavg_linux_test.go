//go:build linux

package system

import "testing"

func TestParseProcLoadavg(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		want    [3]float64
		wantErr bool
	}{
		{"normal", "0.45 1.20 0.85 2/345 67890\n", [3]float64{0.45, 1.20, 0.85}, false},
		{"zeros", "0.00 0.00 0.00 1/1 1\n", [3]float64{0, 0, 0}, false},
		{"high", "99.99 50.50 25.25 0/0 0\n", [3]float64{99.99, 50.50, 25.25}, false},
		{"trailing space", "1.0 2.0 3.0    ", [3]float64{1.0, 2.0, 3.0}, false},
		{"too few fields", "1.0 2.0\n", [3]float64{}, true},
		{"empty", "", [3]float64{}, true},
		{"non-numeric", "a b c d e\n", [3]float64{}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseProcLoadavg(tt.in)
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
