package ssh

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const CacheTTL = 30 * time.Second

// pruneAge is how long stale cache entries (dead panes, dead servers, orphaned
// temp files) survive before Write sweeps them, keeping the cache dir bounded.
const pruneAge = time.Hour

type entry struct {
	User       string    `json:"user"`
	Host       string    `json:"host"`
	Port       string    `json:"port"`
	IsSSH      bool      `json:"is_ssh"`
	ComputedAt time.Time `json:"computed_at"`
}

func CacheRoot() string {
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return filepath.Join(d, "tmux-helper-cache")
	}
	return filepath.Join(os.TempDir(), fmt.Sprintf("tmux-helper-cache-%d", os.Getuid()))
}

func cachePath(serverPID int, paneID string) string {
	pid := strconv.Itoa(serverPID)
	pane := strings.TrimPrefix(paneID, "%")
	return filepath.Join(CacheRoot(), pid, pane+".json")
}

func Read(serverPID int, paneID string) (*Connection, bool) {
	data, err := os.ReadFile(cachePath(serverPID, paneID))
	if err != nil {
		return nil, false
	}
	var e entry
	if err := json.Unmarshal(data, &e); err != nil {
		return nil, false
	}
	if time.Since(e.ComputedAt) > CacheTTL {
		return nil, false
	}
	if !e.IsSSH {
		return nil, true
	}
	return &Connection{User: e.User, Host: e.Host, Port: e.Port}, true
}

func Write(serverPID int, paneID string, conn *Connection) error {
	p := cachePath(serverPID, paneID)
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		return err
	}
	e := entry{ComputedAt: time.Now()}
	if conn != nil {
		e.User = conn.User
		e.Host = conn.Host
		e.Port = conn.Port
		e.IsSSH = true
	}
	data, err := json.Marshal(e)
	if err != nil {
		return err
	}
	// Write to a unique temp file then rename: concurrent status jobs for the
	// same pane each get their own temp file, so they can't corrupt each other.
	f, err := os.CreateTemp(filepath.Dir(p), ".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	if _, err := f.Write(data); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, p); err != nil {
		os.Remove(tmp)
		return err
	}
	prune(CacheRoot())
	return nil
}

// prune removes cache files older than pruneAge and any directories left
// empty, so the cache root can't grow without bound across server restarts
// and pane churn. Best-effort: errors are ignored.
func prune(root string) {
	cutoff := time.Now().Add(-pruneAge)
	dirs, err := os.ReadDir(root)
	if err != nil {
		return
	}
	for _, d := range dirs {
		if !d.IsDir() {
			continue
		}
		dir := filepath.Join(root, d.Name())
		files, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		remaining := len(files)
		for _, f := range files {
			info, err := f.Info()
			if err != nil {
				continue
			}
			if info.ModTime().Before(cutoff) {
				if os.Remove(filepath.Join(dir, f.Name())) == nil {
					remaining--
				}
			}
		}
		if remaining == 0 {
			_ = os.Remove(dir)
		}
	}
}
