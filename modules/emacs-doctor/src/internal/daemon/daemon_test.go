package daemon

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"emacs-doctor/internal/execx"
)

func TestParseShow(t *testing.T) {
	in := "ActiveState=active\nSubState=running\nMainPID=1234\nNRestarts=7\n"
	got := ParseShow(in)
	want := map[string]string{
		"ActiveState": "active",
		"SubState":    "running",
		"MainPID":     "1234",
		"NRestarts":   "7",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("ParseShow = %v, want %v", got, want)
	}
	// A value may itself contain '='; only the first '=' splits.
	if v := ParseShow("Key=a=b")["Key"]; v != "a=b" {
		t.Errorf("ParseShow split on later '=': got %q, want %q", v, "a=b")
	}
}

func TestIsDaemonCmdline(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want bool
	}{
		{"fg-daemon", "/nix/store/x/emacs\x00--init-directory=/y\x00--fg-daemon\x00", true},
		{"daemon", "/nix/store/x/emacs\x00--daemon\x00", true},
		{"named bg-daemon", "/nix/store/x/emacs\x00--bg-daemon=mysrv\x00", true},
		{"named daemon", "/nix/store/x/emacs\x00--daemon=foo\x00", true},
		{"plain editor", "/nix/store/x/emacs\x00-nw\x00file.txt\x00", false},
		// Regression: substring "daemon" in a file/dir arg must NOT match,
		// or reset would SIGKILL an interactive Emacs editing such a file.
		{"editor of daemon-named file", "/nix/store/x/emacs\x00-nw\x00/home/me/daemon-notes.org\x00", false},
		{"init-directory with daemon in path", "/nix/store/x/emacs\x00--init-directory=/etc/daemon/\x00-nw\x00f\x00", false},
		{"empty", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := IsDaemonCmdline([]byte(tt.raw)); got != tt.want {
				t.Errorf("IsDaemonCmdline(%q) = %v, want %v", tt.raw, got, tt.want)
			}
		})
	}
}

func TestParseStatus(t *testing.T) {
	st, err := ParseStatus("ActiveState=active\nSubState=running\nMainPID=1234\nNRestarts=7\n")
	if err != nil {
		t.Fatalf("ParseStatus: unexpected error %v", err)
	}
	want := Status{Known: true, ActiveState: "active", SubState: "running", MainPID: 1234, NRestarts: 7}
	if st != want {
		t.Errorf("ParseStatus = %+v, want %+v", st, want)
	}

	// An inactive unit legitimately reports MainPID=0; that is KNOWN, not unknown.
	st, err = ParseStatus("ActiveState=inactive\nSubState=dead\nMainPID=0\nNRestarts=0\n")
	if err != nil || !st.Known || st.MainPID != 0 {
		t.Errorf("ParseStatus(inactive) = %+v, %v; want Known with MainPID 0", st, err)
	}

	// No MainPID line (empty or truncated output) must not silently become 0.
	for _, in := range []string{"", "ActiveState=active\n", "MainPID=abc\n"} {
		st, err := ParseStatus(in)
		if err == nil || st.Known {
			t.Errorf("ParseStatus(%q) = %+v, %v; want unknown + error", in, st, err)
		}
	}
}

// fakeBin puts an executable shell script called name first on PATH.
func fakeBin(t *testing.T, name, script string) {
	t.Helper()
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("sh not on PATH")
	}
	dir := t.TempDir()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte("#!/bin/sh\n"+script+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// Regression: QueryStatus used to discard the systemctl error, so a failed
// query (no user bus, systemd not running) produced MainPID=0, and status
// then called every live daemon an orphan and told the user to reset it.
func TestQueryStatusSurfacesSystemctlFailure(t *testing.T) {
	// Partial stdout alongside the failure: the exit status, not the absence
	// of a MainPID line, is what must make the state unknown.
	fakeBin(t, "systemctl", `echo "MainPID=0"; echo "Failed to connect to bus" >&2; exit 1`)
	st, err := QueryStatus()
	if err == nil {
		t.Fatal("QueryStatus: want error when systemctl fails, got nil")
	}
	if st.Known {
		t.Errorf("QueryStatus: Known = true after systemctl failure: %+v", st)
	}
}

func TestQueryStatusSuccess(t *testing.T) {
	fakeBin(t, "systemctl", `printf 'ActiveState=active\nSubState=running\nMainPID=42\nNRestarts=1\n'`)
	st, err := QueryStatus()
	if err != nil || !st.Known || st.MainPID != 42 {
		t.Errorf("QueryStatus = %+v, %v; want Known with MainPID 42", st, err)
	}
}

// Regression: every exec used to be unbounded, so a wedged user bus or a busy
// daemon hung `emacs-doctor status` -- the tool you run because things are
// wedged. A hung systemctl/emacsclient must cost at most the budget.
func TestQueriesAreBoundedWhenTheToolHangs(t *testing.T) {
	fakeBin(t, "systemctl", "sleep 30")
	fakeBin(t, "emacsclient", "sleep 30")
	limit := execx.Default + 2*time.Second

	start := time.Now()
	st, err := QueryStatus()
	if elapsed := time.Since(start); elapsed > limit {
		t.Errorf("QueryStatus took %v against a hung systemctl; want <= %v", elapsed, limit)
	}
	if !errors.Is(err, execx.ErrTimeout) || st.Known {
		t.Errorf("QueryStatus = %+v, %v; want unknown + ErrTimeout", st, err)
	}

	start = time.Now()
	if Answers() {
		t.Error("Answers() = true against a hung emacsclient")
	}
	if elapsed := time.Since(start); elapsed > limit {
		t.Errorf("Answers took %v against a hung emacsclient; want <= %v", elapsed, limit)
	}
}

func TestClassify(t *testing.T) {
	known := func(pid int) Status { return Status{Known: true, MainPID: pid} }
	tests := []struct {
		name             string
		pids             []int
		st               Status
		wantManaged      int
		wantOrphans      []int
		wantUnclassified []int
	}{
		{"managed plus orphan", []int{100, 200}, known(100), 100, []int{200}, nil},
		{"only orphan (deadlock)", []int{200}, known(100), 0, []int{200}, nil},
		{"only managed", []int{100}, known(100), 100, nil, nil},
		{"known inactive unit -> all orphans", []int{100, 200}, known(0), 0, []int{100, 200}, nil},
		{"none", nil, known(100), 0, nil, nil},
		// Regression: unknown unit state must never yield orphans -- that is
		// the line that tells the user to run a destructive reset.
		{"unknown status -> unclassified, never orphans", []int{100, 200}, Status{}, 0, nil, []int{100, 200}},
		{"unknown status ignores a stale MainPID", []int{100}, Status{MainPID: 100}, 0, nil, []int{100}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			managed, orphans, unclassified := Classify(tt.pids, tt.st)
			if managed != tt.wantManaged || !reflect.DeepEqual(orphans, tt.wantOrphans) ||
				!reflect.DeepEqual(unclassified, tt.wantUnclassified) {
				t.Errorf("Classify(%v, %+v) = (%d, %v, %v), want (%d, %v, %v)",
					tt.pids, tt.st, managed, orphans, unclassified,
					tt.wantManaged, tt.wantOrphans, tt.wantUnclassified)
			}
		})
	}
}
