package ssh

import (
	"encoding/json"
	"os"
	"path/filepath"
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
	// Construct the entry payload directly with a backdated ComputedAt --
	// no byte surgery on the serialized timestamp (which was TZ- and
	// New-Year's-flaky).
	path := cachePath(42, "%7")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	e := entry{Host: "x", IsSSH: true, ComputedAt: time.Now().Add(-CacheTTL - time.Second)}
	data, err := json.Marshal(e)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	got, hit := Read(42, "%7")
	if hit || got != nil {
		t.Errorf("expected miss after TTL, got hit=%v conn=%+v", hit, got)
	}
}

func TestPrune(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", dir)
	// Seed a stale entry under a dead server pid dir.
	stale := cachePath(41, "%1")
	if err := os.MkdirAll(filepath.Dir(stale), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stale, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-2 * pruneAge)
	if err := os.Chtimes(stale, old, old); err != nil {
		t.Fatal(err)
	}
	// A fresh Write should sweep the stale entry and its now-empty dir.
	if err := Write(42, "%2", nil); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Errorf("stale entry not pruned: stat err = %v", err)
	}
	if _, err := os.Stat(filepath.Dir(stale)); !os.IsNotExist(err) {
		t.Errorf("empty stale dir not pruned: stat err = %v", err)
	}
	// The fresh entry must survive.
	if _, hit := Read(42, "%2"); !hit {
		t.Error("fresh entry pruned or unreadable")
	}
}
