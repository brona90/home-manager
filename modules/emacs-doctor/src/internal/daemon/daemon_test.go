package daemon

import (
	"reflect"
	"testing"
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

func TestClassify(t *testing.T) {
	tests := []struct {
		name        string
		pids        []int
		mainPID     int
		wantManaged int
		wantOrphans []int
	}{
		{"managed plus orphan", []int{100, 200}, 100, 100, []int{200}},
		{"only orphan (deadlock)", []int{200}, 100, 0, []int{200}},
		{"only managed", []int{100}, 100, 100, nil},
		{"no mainpid -> all orphans", []int{100, 200}, 0, 0, []int{100, 200}},
		{"none", nil, 100, 0, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			managed, orphans := Classify(tt.pids, tt.mainPID)
			if managed != tt.wantManaged || !reflect.DeepEqual(orphans, tt.wantOrphans) {
				t.Errorf("Classify(%v, %d) = (%d, %v), want (%d, %v)",
					tt.pids, tt.mainPID, managed, orphans, tt.wantManaged, tt.wantOrphans)
			}
		})
	}
}
