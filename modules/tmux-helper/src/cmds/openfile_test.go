package cmds

import "testing"

func TestParseFileRef(t *testing.T) {
	tests := []struct {
		name           string
		in             string
		wantFile       string
		wantLine, wantCol int
		wantOK         bool
	}{
		{"go file with line+col", "main.go:42:5", "main.go", 42, 5, true},
		{"go file with line", "main.go:42", "main.go", 42, 0, true},
		{"plain path", "src/foo.go", "src/foo.go", 0, 0, true},
		{"absolute path", "/etc/hosts", "/etc/hosts", 0, 0, true},
		{"compiler error", "Error in foo.go:11:14: missing return", "foo.go", 11, 14, true},
		{"home path", "~/.config/foo.toml:7", "~/.config/foo.toml", 7, 0, true},
		{"no file", "10:30 PM", "", 0, 0, false},
		{"empty", "", "", 0, 0, false},
		{"plain word", "hello world", "", 0, 0, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f, l, c, ok := parseFileRef(tt.in)
			if ok != tt.wantOK {
				t.Errorf("ok=%v want %v", ok, tt.wantOK)
			}
			if !ok {
				return
			}
			if f != tt.wantFile || l != tt.wantLine || c != tt.wantCol {
				t.Errorf("got (%q, %d, %d) want (%q, %d, %d)", f, l, c, tt.wantFile, tt.wantLine, tt.wantCol)
			}
		})
	}
}
