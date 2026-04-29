//go:build darwin

package system

import (
	"strconv"
	"testing"
	"time"
)

func TestParseDarwinBoottime(t *testing.T) {
	now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	cases := []struct {
		name string
		ago  time.Duration
	}{
		{"3h ago", 3 * time.Hour},
		{"5d ago", 5 * 24 * time.Hour},
		{"1m ago", time.Minute},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			bootSec := now.Add(-tc.ago).Unix()
			in := "{ sec = " + strconv.FormatInt(bootSec, 10) + ", usec = 0 } Sun Apr 28 2026"
			d, err := parseDarwinBoottime(in, now)
			if err != nil {
				t.Fatal(err)
			}
			if d != tc.ago {
				t.Errorf("got %v, want %v", d, tc.ago)
			}
		})
	}
}

func TestParseDarwinBoottime_Future(t *testing.T) {
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	bootSec := now.Add(time.Hour).Unix()
	in := "{ sec = " + strconv.FormatInt(bootSec, 10) + ", usec = 0 }"
	if _, err := parseDarwinBoottime(in, now); err == nil {
		t.Error("expected error for future boot time")
	}
}

func TestParseDarwinBoottime_Garbage(t *testing.T) {
	for _, s := range []string{
		"",
		"hello",
		"{ secn = 100 }",
		"{ sec = abc, usec = 0 }",
	} {
		if _, err := parseDarwinBoottime(s, time.Now()); err == nil {
			t.Errorf("expected error for %q", s)
		}
	}
}
