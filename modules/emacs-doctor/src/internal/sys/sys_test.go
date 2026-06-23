package sys

import "testing"

func TestParseLoadAvg(t *testing.T) {
	tests := []struct {
		name       string
		in         string
		wantOne    float64
		wantTriple string
		wantOK     bool
	}{
		{"typical", "8.83 4.89 3.25 2/905 532574\n", 8.83, "8.83 4.89 3.25", true},
		{"three only", "0.10 0.20 0.30", 0.10, "0.10 0.20 0.30", true},
		{"too few", "1.0 2.0", 0, "", false},
		{"garbage", "abc def ghi", 0, "", false},
		{"empty", "", 0, "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			one, triple, ok := ParseLoadAvg(tt.in)
			if ok != tt.wantOK || one != tt.wantOne || triple != tt.wantTriple {
				t.Errorf("ParseLoadAvg(%q) = (%v, %q, %v), want (%v, %q, %v)",
					tt.in, one, triple, ok, tt.wantOne, tt.wantTriple, tt.wantOK)
			}
		})
	}
}
