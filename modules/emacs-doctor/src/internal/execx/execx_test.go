package execx

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func needSh(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("sh not on PATH")
	}
}

func TestRunReturnsStdout(t *testing.T) {
	needSh(t)
	out, err := Run(Default, "sh", "-c", "echo hello")
	if err != nil {
		t.Fatalf("Run: unexpected error %v", err)
	}
	if strings.TrimSpace(out) != "hello" {
		t.Errorf("Run stdout = %q, want %q", out, "hello\n")
	}
}

func TestRunNonZeroExitIsNotTimeout(t *testing.T) {
	needSh(t)
	_, err := Run(Default, "sh", "-c", "exit 3")
	if err == nil {
		t.Fatal("Run: want error for exit 3, got nil")
	}
	if errors.Is(err, ErrTimeout) {
		t.Errorf("Run: exit 3 reported as timeout: %v", err)
	}
}

// A command that outlives its budget is killed and reported as ErrTimeout,
// promptly -- the whole point is that a wedged systemctl/emacsclient can no
// longer hang `emacs-doctor status` forever.
func TestRunTimesOut(t *testing.T) {
	needSh(t)
	start := time.Now()
	_, err := Run(100*time.Millisecond, "sh", "-c", "sleep 30")
	elapsed := time.Since(start)
	if !errors.Is(err, ErrTimeout) {
		t.Errorf("Run: want ErrTimeout, got %v", err)
	}
	if elapsed > 3*time.Second {
		t.Errorf("Run took %v to give up on a 100ms budget", elapsed)
	}
}

// The child forks a grandchild that inherits stdout. Killing the child alone
// leaves the pipe open, and a bare CommandContext().Output() then blocks until
// the grandchild exits (30s here). WaitDelay is what bounds this case.
func TestRunTimesOutWithGrandchildHoldingStdout(t *testing.T) {
	needSh(t)
	start := time.Now()
	_, err := Run(100*time.Millisecond, "sh", "-c", "sleep 30; :")
	elapsed := time.Since(start)
	if !errors.Is(err, ErrTimeout) {
		t.Errorf("Run: want ErrTimeout, got %v", err)
	}
	if elapsed > 3*time.Second {
		t.Errorf("Run took %v; a grandchild holding stdout defeated the timeout", elapsed)
	}
}

// WaitDelay alone would make the previous test pass while leaving the
// grandchild running. This pins the process-group kill: the backgrounded
// sleep must be dead once Run returns, not merely detached from our pipe.
func TestRunKillsTheWholeProcessGroup(t *testing.T) {
	needSh(t)
	pidFile := filepath.Join(t.TempDir(), "pid")
	_, err := Run(200*time.Millisecond, "sh", "-c", `sleep 30 & echo $! > "$1"; wait`, "sh", pidFile)
	if !errors.Is(err, ErrTimeout) {
		t.Fatalf("Run: want ErrTimeout, got %v", err)
	}
	raw, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatalf("grandchild never wrote its PID: %v", err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatalf("bad PID %q: %v", raw, err)
	}
	// Reparenting and reaping are asynchronous; a zombie counts as dead.
	deadline := time.Now().Add(2 * time.Second)
	for alive(pid) {
		if time.Now().After(deadline) {
			_ = syscall.Kill(pid, syscall.SIGKILL)
			t.Fatalf("grandchild PID %d survived the timeout: the process group was not killed", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// alive reports whether pid exists and is not a zombie.
func alive(pid int) bool {
	stat, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat")
	if err != nil {
		return false
	}
	// The state field follows the parenthesised comm, which may contain spaces.
	s := string(stat)
	i := strings.LastIndexByte(s, ')')
	if i < 0 || i+2 >= len(s) {
		return false
	}
	return s[i+2] != 'Z'
}

func TestRunMissingBinary(t *testing.T) {
	_, err := Run(Default, "emacs-doctor-no-such-binary-xyz")
	if err == nil {
		t.Fatal("Run: want error for a missing binary, got nil")
	}
	if errors.Is(err, ErrTimeout) {
		t.Errorf("Run: missing binary reported as timeout: %v", err)
	}
}
