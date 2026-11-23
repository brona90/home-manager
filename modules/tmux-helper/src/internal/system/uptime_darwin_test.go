//go:build darwin

package system

import (
	"context"
	"os"
	"os/exec"
	"strconv"
	"testing"
	"time"
)

// TestUptimeHelperProcess is not a test: it is the fake `sysctl` that
// TestUptimeIsBounded execs, re-entering this test binary (the os/exec
// helper-process pattern). It sleeps for FAKE_SYSCTL_SLEEP, then exits 0.
func TestUptimeHelperProcess(t *testing.T) {
	if os.Getenv("FAKE_SYSCTL") != "1" {
		return
	}
	d, err := time.ParseDuration(os.Getenv("FAKE_SYSCTL_SLEEP"))
	if err != nil {
		os.Exit(2)
	}
	time.Sleep(d)
	os.Exit(0)
}

func TestUptimeIsBounded(t *testing.T) {
	origCmd, origTimeout := sysctlCommand, uptimeTimeout
	t.Cleanup(func() { sysctlCommand, uptimeTimeout = origCmd, origTimeout })
	uptimeTimeout = 100 * time.Millisecond
	sysctlCommand = func(ctx context.Context, args ...string) *exec.Cmd {
		cmd := exec.CommandContext(ctx, os.Args[0],
			append([]string{"-test.run=^TestUptimeHelperProcess$", "--"}, args...)...)
		cmd.Env = append(os.Environ(), "FAKE_SYSCTL=1", "FAKE_SYSCTL_SLEEP=10s")
		return cmd
	}
	start := time.Now()
	if _, err := Uptime(); err == nil {
		t.Fatal("Uptime against a hung sysctl returned nil; want an error")
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("Uptime took %v against a hung sysctl; the bound is not applied", elapsed)
	}
}

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
