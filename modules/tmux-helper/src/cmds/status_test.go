package cmds

import "testing"

func TestLLMNameFromComm(t *testing.T) {
	tests := []struct {
		name string
		comm string
		want string
	}{
		{"bare name", "claude", "claude"},
		{"nix wrapped", ".claude-wrapped", "claude"},
		{"darwin full path", "/usr/local/bin/claude", "claude"},
		{"darwin full path nix wrapped", "/nix/store/abc123-claude-code-1.2.3/bin/.claude-wrapped", "claude"},
		{"suffixed", "claude-code", "claude"},
		{"darwin full path suffixed", "/nix/store/abc123/bin/ollama-server", "ollama"},
		{"upper case", "Claude", "claude"},
		{"aider", "aider", "aider"},
		{"unrelated", "zsh", ""},
		{"unrelated path", "/bin/zsh", ""},
		{"prefix without dash no match", "claudezilla", ""},
		{"empty", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := llmNameFromComm(tt.comm); got != tt.want {
				t.Errorf("llmNameFromComm(%q) = %q, want %q", tt.comm, got, tt.want)
			}
		})
	}
}
