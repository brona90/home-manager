//go:build darwin

package system

import "testing"

func TestParseDarwinLoadavg(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		want    [3]float64
		wantErr bool
	}{
		{"normal", "{ 0.45 1.20 0.85 }\n", [3]float64{0.45, 1.20, 0.85}, false},
		{"zeros", "{ 0.00 0.00 0.00 }\n", [3]float64{0, 0, 0}, false},
		{"no braces", "1.0 2.0 3.0\n", [3]float64{1.0, 2.0, 3.0}, false},
		{"too few", "{ 1.0 2.0 }\n", [3]float64{}, true},
		{"empty", "", [3]float64{}, true},
		{"garbage", "{ a b c }\n", [3]float64{}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseDarwinLoadavg(tt.in)
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
