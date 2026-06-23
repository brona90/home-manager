// Package daemon wraps the systemd-managed Emacs daemon: querying its unit
// state, discovering daemon processes (and orphans squatting the server
// socket), talking to it via emacsclient, and the reset/recovery primitives.
//
// The pure parsing/classification helpers (ParseShow, IsDaemonCmdline,
// Classify) are kept side-effect-free so they can be unit tested without a
// live system.
package daemon

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

const serviceUnit = "emacs"

// run executes a command and returns its stdout. A non-zero exit (e.g. pgrep
// with no matches, emacsclient with no daemon) surfaces as a non-nil error.
func run(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).Output()
	return string(out), err
}

// ---------------------------------------------------------------- unit state

// Status is the subset of `systemctl show` fields we care about.
type Status struct {
	ActiveState string
	SubState    string
	MainPID     int
	NRestarts   int // -1 when unknown
}

// ParseShow turns `key=value` lines (systemctl show output) into a map.
func ParseShow(out string) map[string]string {
	m := map[string]string{}
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimRight(line, "\r")
		if i := strings.IndexByte(line, '='); i > 0 {
			m[line[:i]] = line[i+1:]
		}
	}
	return m
}

// QueryStatus reads the live unit state of the user emacs.service.
func QueryStatus() Status {
	out, _ := run("systemctl", "--user", "show", serviceUnit,
		"-p", "ActiveState", "-p", "SubState", "-p", "MainPID", "-p", "NRestarts")
	m := ParseShow(out)
	return Status{
		ActiveState: m["ActiveState"],
		SubState:    m["SubState"],
		MainPID:     atoiOr(m["MainPID"], 0),
		NRestarts:   atoiOr(m["NRestarts"], -1),
	}
}

func atoiOr(s string, def int) int {
	if n, err := strconv.Atoi(strings.TrimSpace(s)); err == nil {
		return n
	}
	return def
}

// ---------------------------------------------------------------- processes

// IsDaemonCmdline reports whether a /proc/<pid>/cmdline (NUL-separated)
// belongs to an Emacs daemon (--daemon or --fg-daemon).
func IsDaemonCmdline(raw []byte) bool {
	return strings.Contains(string(raw), "daemon")
}

// pgrepEmacs returns PIDs whose comm is exactly "emacs" (never matches this
// tool, whose comm is emacs-doctor).
func pgrepEmacs() []int {
	out, _ := run("pgrep", "-x", "emacs")
	var pids []int
	for _, f := range strings.Fields(out) {
		if n, err := strconv.Atoi(f); err == nil {
			pids = append(pids, n)
		}
	}
	return pids
}

func isDaemonProc(pid int) bool {
	raw, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "cmdline"))
	if err != nil {
		return false
	}
	return IsDaemonCmdline(raw)
}

// DaemonProcs returns the PIDs of running Emacs daemon processes.
func DaemonProcs() []int {
	var ds []int
	for _, p := range pgrepEmacs() {
		if isDaemonProc(p) {
			ds = append(ds, p)
		}
	}
	return ds
}

// Classify splits daemon PIDs into the systemd-managed one (== mainPID) and
// any orphans. managed is 0 when none of the PIDs match mainPID.
func Classify(daemonPIDs []int, mainPID int) (managed int, orphans []int) {
	for _, p := range daemonPIDs {
		if mainPID != 0 && p == mainPID {
			managed = p
		} else {
			orphans = append(orphans, p)
		}
	}
	return managed, orphans
}

// ---------------------------------------------------------------- emacsclient

func eval(form string) (string, bool) {
	out, err := run("emacsclient", "-e", form)
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(out), true
}

// Answers reports whether a daemon is currently accepting connections.
func Answers() bool {
	_, ok := eval("t")
	return ok
}

// SocketOwnerPID returns the PID of the daemon currently holding the socket.
func SocketOwnerPID() (int, bool) {
	s, ok := eval("(emacs-pid)")
	if !ok {
		return 0, false
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0, false
	}
	return n, true
}

// OpenFileBuffers returns the number of file-visiting buffers.
func OpenFileBuffers() (int, bool) {
	s, ok := eval("(length (delq nil (mapcar (function buffer-file-name) (buffer-list))))")
	if !ok {
		return 0, false
	}
	n, err := strconv.Atoi(s)
	return n, err == nil
}

// UnsavedCount returns the number of modified file-visiting buffers.
func UnsavedCount() (int, bool) {
	s, ok := eval("(length (delq nil (mapcar (lambda (b) (and (buffer-file-name b) (buffer-modified-p b))) (buffer-list))))")
	if !ok {
		return 0, false
	}
	n, err := strconv.Atoi(s)
	return n, err == nil
}

// UnsavedFiles returns the Lisp read-syntax list of modified buffer file names
// (e.g. `("/a" "/b")`), or "nil"/"" when none.
func UnsavedFiles() string {
	s, _ := eval("(delq nil (mapcar (lambda (b) (and (buffer-file-name b) (buffer-modified-p b) (buffer-file-name b))) (buffer-list)))")
	return s
}

// ---------------------------------------------------------------- recovery

// SocketPaths lists candidate server-socket locations for the default daemon.
func SocketPaths() []string {
	uid := strconv.Itoa(os.Getuid())
	rt := os.Getenv("XDG_RUNTIME_DIR")
	if rt == "" {
		rt = "/run/user/" + uid
	}
	tmp := os.Getenv("TMPDIR")
	if tmp == "" {
		tmp = "/tmp"
	}
	return []string{
		filepath.Join(rt, "emacs", "server"),
		filepath.Join(tmp, "emacs"+uid, "server"),
	}
}

// StopService stops the managed unit (best effort).
func StopService() { _, _ = run("systemctl", "--user", "stop", serviceUnit) }

// ResetFailed clears the unit's failure bookkeeping (best effort).
func ResetFailed() { _, _ = run("systemctl", "--user", "reset-failed", serviceUnit) }

// StartService starts the managed unit, returning any start error.
func StartService() error {
	return exec.Command("systemctl", "--user", "start", serviceUnit).Run()
}

func killDaemons(sig syscall.Signal) int {
	n := 0
	for _, p := range DaemonProcs() {
		if syscall.Kill(p, sig) == nil {
			n++
		}
	}
	return n
}

// TermDaemons sends SIGTERM to all daemon processes; returns the count signaled.
func TermDaemons() int { return killDaemons(syscall.SIGTERM) }

// KillDaemons sends SIGKILL to any surviving daemon processes.
func KillDaemons() int { return killDaemons(syscall.SIGKILL) }

// RemoveStaleSockets deletes any present server sockets, returning those removed.
func RemoveStaleSockets() []string {
	var removed []string
	for _, p := range SocketPaths() {
		if _, err := os.Stat(p); err == nil {
			if os.Remove(p) == nil {
				removed = append(removed, p)
			}
		}
	}
	return removed
}
