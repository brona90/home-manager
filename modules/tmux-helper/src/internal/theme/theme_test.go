package theme

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

var testThemes = Themes{
	"alpha":   Palette{StatusFg: "#aaa", StatusBg: "#000"},
	"bravo":   Palette{StatusFg: "#bbb", StatusBg: "#111"},
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

func TestStatusJobWord(t *testing.T) {
	tests := []struct{ in, want string }{
		{"/nix/store/abc-tmux-helper/bin/tmux-helper", `'/nix/store/abc-tmux-helper/bin/tmux-helper'`},
		{"/opt/my tools/tmux-helper", `'/opt/my tools/tmux-helper'`},
		// sh metacharacters are inert inside single quotes.
		{"/a/$HOME/`id`;b", "'/a/$HOME/`id`;b'"},
		// An embedded single quote uses the standard close-escape-reopen.
		{"/a/it's", `'/a/it'"'"'s'`},
		// tmux format-expands the job command (#S is the session name) and
		// its ## escape is irregular (##[ is kept as ##[), so # never
		// appears literally; sh regenerates it from octal.
		{"/a/#S", `'/a/'"$(printf '\043')"'S'`},
		{"/a/#[b", `'/a/'"$(printf '\043')"'[b'`},
		// tmux strftime()s the job command (%b is the month), so % is
		// regenerated from octal too.
		{"/a/%b", `'/a/'"$(printf '\045')"'b'`},
		// tmux ends #( at the first unbalanced ), ignoring sh quoting, so
		// parens never appear literally either.
		{"/a)b", `'/a'"$(printf '\051')"'b'`},
		{"(x", `"$(printf '\050')"'x'`},
		// Braces and commas are only special to tmux after a #.
		{"/a/{b},c", `'/a/{b},c'`},
		{"", `''`},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			if got := statusJobWord(tt.in); got != tt.want {
				t.Errorf("statusJobWord(%q)\n got  %s\n want %s", tt.in, got, tt.want)
			}
		})
	}
}

// TestStatusJobWordSurvives checks the word means the right thing, not just
// that it is spelled as above: sh must turn it back into exactly the input,
// and tmux must have nothing to act on -- no # or % at all, and parens that
// never close below depth zero (an early ")" ends the #() job).
func TestStatusJobWordSurvives(t *testing.T) {
	for _, in := range []string{
		"/opt/my tools/tmux-helper",
		"/a/#S/#H/#{pane_id}/##[x]/#[fg=red]/#,/#}",
		"/a/%b/%%/100%",
		"/a/(b)/c)d(/((",
		"/a/$HOME/`id`;b/it's/\"q\"/\\n/*/{x,y}",
	} {
		word := statusJobWord(in)
		if strings.ContainsAny(word, "#%") {
			t.Errorf("statusJobWord(%q) = %s contains # or %%, which tmux rewrites", in, word)
		}
		depth := 0
		for _, r := range word {
			switch r {
			case '(':
				depth++
			case ')':
				depth--
			}
			if depth < 0 {
				t.Errorf("statusJobWord(%q) = %s closes a paren early, ending the #() job", in, word)
				break
			}
		}
		out, err := exec.Command("sh", "-c", "printf '%s' "+word).Output()
		if err != nil {
			t.Fatalf("sh -c on statusJobWord(%q): %v", in, err)
		}
		if string(out) != in {
			t.Errorf("sh decoded statusJobWord(%q) as %q", in, out)
		}
	}
}

// TestSetCommandsQuotesHelper checks the encoded helper word -- never the raw
// path -- reaches every #() job in status-left and status-right.
func TestSetCommandsQuotesHelper(t *testing.T) {
	bin := "/opt/my tools (x)/tmux-helper"
	cmds, err := testThemes.SetCommands("alpha", bin)
	if err != nil {
		t.Fatal(err)
	}
	word := statusJobWord(bin)
	seen := 0
	for _, c := range cmds {
		if c[2] != "status-left" && c[2] != "status-right" {
			continue
		}
		seen++
		if strings.Contains(c[3], "#("+bin) {
			t.Errorf("%s embeds the raw helper path: %s", c[2], c[3])
		}
		if n := strings.Count(c[3], "#("+word+" "); n == 0 {
			t.Errorf("%s has no #() job using the quoted helper word: %s", c[2], c[3])
		}
	}
	if seen != 2 {
		t.Fatalf("found %d status-left/right commands, want 2", seen)
	}
}

func TestSetCommands_Unknown(t *testing.T) {
	if _, err := testThemes.SetCommands("nope", "/bin/tmux-helper"); err == nil {
		t.Error("expected error for unknown theme")
	}
}
