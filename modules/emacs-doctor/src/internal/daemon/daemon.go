// Package daemon wraps the systemd-managed Emacs daemon: querying its unit
// state, discovering daemon processes (and orphans squatting the server
// socket), talking to it via emacsclient, and the reset/recovery primitives.
//
// The pure parsing/classification helpers (ParseShow, ParseStatus,
// IsDaemonCmdline, Classify) are kept side-effect-free so they can be unit tested without a
// live system.
package daemon

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"emacs-doctor/internal/execx"
)

const serviceUnit = "emacs"

// unitJobTimeout bounds `systemctl start` and `systemctl stop`. These block
// until the job finishes, and emacs.service is Type=notify: start returns only
// once init.el has loaded, which was measured at 17s on this machine. A short
// budget would kill the systemctl client while systemd carries on with the
// job, and reset would report a start failure for a daemon that is merely
// still loading. So the bound sits just above systemd's own
// TimeoutStartUSec/TimeoutStopUSec (90s default): systemd fails the job first,
// and the timeout only catches a systemctl that is itself wedged.
const unitJobTimeout = 100 * time.Second

// run executes a quick command (execx.Default budget) and returns its stdout.
// A non-zero exit (e.g. pgrep with no matches, emacsclient with no daemon) or
// an expired budget surfaces as a non-nil error.
func run(name string, args ...string) (string, error) {
	return execx.Run(execx.Default, name, args...)
}

// ---------------------------------------------------------------- unit state

// Status is the subset of `systemctl show` fields we care about.
//
// Known is false when the unit state could not be read (systemctl failed,
// timed out, or returned no usable MainPID). MainPID is then meaningless --
// in particular it is NOT "no managed daemon" -- and nothing may be
// classified against it.
type Status struct {
	Known       bool
	ActiveState string
	SubState    string
	MainPID     int
	NRestarts   int // -1 when unknown
}

// ParseStatus builds a Status from `systemctl show` output. It errors (and
// leaves Known false) when MainPID is absent or unparseable, since a missing
// MainPID would otherwise read as 0, i.e. "every daemon is an orphan".
func ParseStatus(out string) (Status, error) {
	m := ParseShow(out)
	st := Status{
		ActiveState: m["ActiveState"],
		SubState:    m["SubState"],
		NRestarts:   atoiOr(m["NRestarts"], -1),
	}
	raw, present := m["MainPID"]
	pid, err := strconv.Atoi(strings.TrimSpace(raw))
	if !present || err != nil {
		return st, errors.New("systemctl show: no usable MainPID")
	}
	st.MainPID = pid
	st.Known = true
	return st, nil
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

// QueryStatus reads the live unit state of the user emacs.service. On error
// the returned Status has Known == false and must be reported as unknown.
func QueryStatus() (Status, error) {
	out, err := run("systemctl", "--user", "show", serviceUnit,
		"-p", "ActiveState", "-p", "SubState", "-p", "MainPID", "-p", "NRestarts")
	if err != nil {
		return Status{NRestarts: -1}, fmt.Errorf("systemctl --user show %s: %w", serviceUnit, err)
	}
	return ParseStatus(out)
}

func atoiOr(s string, def int) int {
	if n, err := strconv.Atoi(strings.TrimSpace(s)); err == nil {
		return n
	}
	return def
}

// ---------------------------------------------------------------- processes

// IsDaemonCmdline reports whether a /proc/<pid>/cmdline (NUL-separated)
// belongs to an Emacs daemon. It matches the exact daemon flag as its own
// argument — NOT a substring — so a normal `emacs -nw ~/daemon-notes.org` or
// `--init-directory=/etc/daemon/` is never misclassified (and never killed by
// reset). Emacs accepts --daemon, --bg-daemon, --fg-daemon, each optionally
// with an =NAME suffix.
func IsDaemonCmdline(raw []byte) bool {
	for _, f := range strings.Split(string(raw), "\x00") {
		if f == "--daemon" || f == "--bg-daemon" || f == "--fg-daemon" ||
			strings.HasPrefix(f, "--daemon=") ||
			strings.HasPrefix(f, "--bg-daemon=") ||
			strings.HasPrefix(f, "--fg-daemon=") {
			return true
		}
	}
	return false
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

// Classify splits daemon PIDs into the systemd-managed one (== st.MainPID)
// and any orphans. managed is 0 when none of the PIDs match MainPID.
//
// When st is not Known, every PID comes back in unclassified and orphans is
// empty: without the unit's MainPID there is no way to tell the managed daemon
// from a squatter, and "orphan" is the verdict that sends the user to a
// destructive reset.
func Classify(daemonPIDs []int, st Status) (managed int, orphans, unclassified []int) {
	if !st.Known {
		return 0, nil, append(unclassified, daemonPIDs...)
	}
	for _, p := range daemonPIDs {
		if st.MainPID != 0 && p == st.MainPID {
			managed = p
		} else {
			orphans = append(orphans, p)
		}
	}
	return managed, orphans, nil
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
func StopService() {
	_, _ = execx.Run(unitJobTimeout, "systemctl", "--user", "stop", serviceUnit)
}

// ResetFailed clears the unit's failure bookkeeping (best effort).
func ResetFailed() { _, _ = run("systemctl", "--user", "reset-failed", serviceUnit) }

// StartService starts the managed unit, returning any start error.
func StartService() error {
	_, err := execx.Run(unitJobTimeout, "systemctl", "--user", "start", serviceUnit)
	return err
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
