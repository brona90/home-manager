package cmds

import "testing"

func TestNavigateKeys(t *testing.T) {
	tests := []struct {
		dir, flag, vim string
		ok             bool
	}{
		{"left", "-L", "h", true},
		{"down", "-D", "j", true},
		{"up", "-U", "k", true},
		{"right", "-R", "l", true},
		{"sideways", "", "", false},
		{"", "", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.dir, func(t *testing.T) {
			f, v, ok := navigateKeys(tt.dir)
			if ok != tt.ok || f != tt.flag || v != tt.vim {
				t.Errorf("navigateKeys(%q) = (%q,%q,%v), want (%q,%q,%v)", tt.dir, f, v, ok, tt.flag, tt.vim, tt.ok)
			}
		})
	}
}

func TestIsVim(t *testing.T) {
	for _, cmd := range []string{"vim", "vi", "nvim", "neovim", "vimr", "vimx", "nvim-qt"} {
		if !isVim(cmd) {
			t.Errorf("isVim(%q) = false, want true", cmd)
		}
	}
	for _, cmd := range []string{"emacs", "bash", "zsh", "less", "more", "tmux", "vi-improved", "", "VIM"} {
		if isVim(cmd) {
			t.Errorf("isVim(%q) = true, want false", cmd)
		}
	}
}
