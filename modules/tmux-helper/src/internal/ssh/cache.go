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
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}
