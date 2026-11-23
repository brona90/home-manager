package clipboard

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestHelperProcess is not a test: it is the fake clipboard tool the tests
// below exec, re-entering this test binary (the standard os/exec
// helper-process pattern). It copies stdin to FAKE_CLIP_OUT, sleeps for
// FAKE_CLIP_SLEEP, then exits 0, so the timeout path kills a real child.
func TestHelperProcess(t *testing.T) {
	if os.Getenv("FAKE_CLIP") != "1" {
		return
	}
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		os.Exit(2)
	}
	if err := os.WriteFile(os.Getenv("FAKE_CLIP_OUT"), data, 0o600); err != nil {
		os.Exit(2)
	}
	d, err := time.ParseDuration(os.Getenv("FAKE_CLIP_SLEEP"))
	if err != nil {
		os.Exit(2)
	}
	time.Sleep(d)
	os.Exit(0)
}

// fakeBackend returns a Backend running TestHelperProcess with the given
// sleep, shrinks copyTimeout to bound, and returns the file the fake writes
// its stdin to.
func fakeBackend(t *testing.T, sleep, bound time.Duration) (*Backend, string) {
	t.Helper()
	orig := copyTimeout
	t.Cleanup(func() { copyTimeout = orig })
	copyTimeout = bound
	out := filepath.Join(t.TempDir(), "clip")
	t.Setenv("FAKE_CLIP", "1")
	t.Setenv("FAKE_CLIP_OUT", out)
	t.Setenv("FAKE_CLIP_SLEEP", sleep.String())
	return &Backend{Name: "fake", Argv: []string{os.Args[0], "-test.run=^TestHelperProcess$"}}, out
}

func TestRunBackendPipesStdin(t *testing.T) {
	b, out := fakeBackend(t, 0, 5*time.Second)
	if err := runBackend(b, strings.NewReader("héllo")); err != nil {
		t.Fatalf("runBackend: %v", err)
	}
	got, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "héllo" {
		t.Errorf("backend received %q, want %q", got, "héllo")
	}
}

func TestRunBackendIsBounded(t *testing.T) {
	b, _ := fakeBackend(t, 10*time.Second, 100*time.Millisecond)
	start := time.Now()
	err := runBackend(b, strings.NewReader("x"))
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("runBackend took %v against a hung clipboard tool; the bound is not applied", elapsed)
	}
	if err == nil {
		t.Fatal("runBackend against a hung clipboard tool returned nil; want a timeout error")
	}
	if !strings.Contains(err.Error(), "timed out") {
		t.Errorf("error %q should say it timed out", err)
	}
}
