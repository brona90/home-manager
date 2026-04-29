package theme

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

var testThemes = Themes{
	"alpha": Palette{StatusFg: "#aaa", StatusBg: "#000"},
	"bravo": Palette{StatusFg: "#bbb", StatusBg: "#111"},
	"charlie": Palette{StatusFg: "#ccc", StatusBg: "#222"},
}

func writeTempThemes(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "themes.json")
	data, _ := json.Marshal(testThemes)
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoad(t *testing.T) {
	path := writeTempThemes(t)
	got, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 {
		t.Errorf("got %d themes, want 3", len(got))
	}
	if got["alpha"].StatusFg != "#aaa" {
		t.Errorf("alpha StatusFg = %q, want #aaa", got["alpha"].StatusFg)
	}
}

func TestLoad_Missing(t *testing.T) {
	if _, err := Load("/no/such/file"); err == nil {
		t.Error("expected error for missing file")
	}
}

func TestNames(t *testing.T) {
	got := testThemes.Names()
	want := []string{"alpha", "bravo", "charlie"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i, n := range want {
		if got[i] != n {
			t.Errorf("got[%d] = %q, want %q", i, got[i], n)
		}
	}
}

func TestNext(t *testing.T) {
	tests := []struct {
		current, next string
	}{
		{"alpha", "bravo"},
		{"bravo", "charlie"},
		{"charlie", "alpha"},
		{"unknown", "alpha"},
		{"", "alpha"},
	}
	for _, tt := range tests {
		t.Run(tt.current, func(t *testing.T) {
			if got := testThemes.Next(tt.current); got != tt.next {
				t.Errorf("Next(%q) = %q, want %q", tt.current, got, tt.next)
			}
		})
	}
}

func TestSetCommands(t *testing.T) {
	cmds, err := testThemes.SetCommands("alpha", "/bin/tmux-helper")
	if err != nil {
		t.Fatal(err)
	}
	if len(cmds) == 0 {
		t.Fatal("no commands emitted")
	}
	// Spot-check: the first emitted command should be a set-option for
	// pane-border-style with the alpha palette's color (zero value here).
	first := cmds[0]
	if first[0] != "set-option" || first[1] != "-g" {
		t.Errorf("first cmd = %v, want set-option -g ...", first)
	}
}

func TestSetCommands_Unknown(t *testing.T) {
	if _, err := testThemes.SetCommands("nope", "/bin/tmux-helper"); err == nil {
		t.Error("expected error for unknown theme")
	}
}
