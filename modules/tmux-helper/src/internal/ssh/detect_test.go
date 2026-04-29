package ssh

import "testing"

func TestParseSSHG(t *testing.T) {
	out := `user gfoster
hostname jumpbox.example.com
port 2222
identityfile ~/.ssh/id_ed25519
addressfamily any
forwardagent no
`
	c := parseSSHG(out)
	if c.User != "gfoster" || c.Host != "jumpbox.example.com" || c.Port != "2222" {
		t.Errorf("got %+v, want gfoster@jumpbox.example.com:2222", c)
	}
}

func TestParseSSHG_Empty(t *testing.T) {
	c := parseSSHG("")
	if c.User != "" || c.Host != "" || c.Port != "" {
		t.Errorf("expected empty Connection, got %+v", c)
	}
}

func TestDetectFromArgv(t *testing.T) {
	tests := []struct {
		name string
		argv []string
		want Connection
	}{
		{"user@host", []string{"user@host.example"}, Connection{User: "user", Host: "host.example"}},
		{"host only", []string{"jumpbox"}, Connection{Host: "jumpbox"}},
		{"with port", []string{"-p", "2222", "user@host"}, Connection{User: "user", Host: "host", Port: "2222"}},
		{"flags ignored", []string{"-v", "-T", "user@host"}, Connection{User: "user", Host: "host"}},
		{"empty", []string{}, Connection{}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := detectFromArgv(tt.argv)
			if *got != tt.want {
				t.Errorf("got %+v, want %+v", *got, tt.want)
			}
		})
	}
}
