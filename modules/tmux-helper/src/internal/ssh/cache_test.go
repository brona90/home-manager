package ssh

import (
	"os"
	"testing"
	"time"
)

func TestRoundTrip(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	conn := &Connection{User: "alice", Host: "host.example", Port: "22"}
	if err := Write(42, "%5", conn); err != nil {
		t.Fatal(err)
	}
	got, hit := Read(42, "%5")
	if !hit || got == nil {
		t.Fatalf("expected hit, got hit=%v conn=%v", hit, got)
	}
	if *got != *conn {
		t.Errorf("got %+v, want %+v", *got, *conn)
	}
}

func TestNotSSHCachedAsHit(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	if err := Write(42, "%6", nil); err != nil {
		t.Fatal(err)
	}
	got, hit := Read(42, "%6")
	if !hit {
		t.Errorf("nil entry should be cached as hit (avoids re-walking)")
	}
	if got != nil {
		t.Errorf("got %+v, want nil", got)
	}
}

func TestMissOnNoFile(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	got, hit := Read(42, "%99")
	if hit || got != nil {
		t.Errorf("expected miss, got hit=%v conn=%v", hit, got)
	}
}

func TestExpiry(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", dir)
	if err := Write(42, "%7", &Connection{Host: "x"}); err != nil {
		t.Fatal(err)
	}
	// Backdate the file's mtime won't help since we read computed_at from
	// the entry payload. Mutate the payload directly.
	path := cachePath(42, "%7")
	data, _ := os.ReadFile(path)
	// Cheap surgery: replace today's RFC3339 timestamp with a year-ago one.
	old := time.Now().UTC().Format("2006")
	tagged := []byte(string(data))
	for i, b := range tagged {
		if b == '"' && i+5 < len(tagged) && string(tagged[i+1:i+5]) == old {
			// Replace the year digits.
			copy(tagged[i+1:i+5], []byte("2000"))
			break
		}
	}
	_ = os.WriteFile(path, tagged, 0o600)
	got, hit := Read(42, "%7")
	if hit || got != nil {
		t.Errorf("expected miss after TTL, got hit=%v conn=%+v", hit, got)
	}
}
