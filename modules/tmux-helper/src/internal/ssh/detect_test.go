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
		{"identity file value not host", []string{"-i", "key", "host"}, Connection{Host: "host"}},
		{"option value not host", []string{"-o", "StrictHostKeyChecking=no", "host"}, Connection{Host: "host"}},
		{"login flag sets user", []string{"-l", "alice", "host"}, Connection{User: "alice", Host: "host"}},
		{"jump host value skipped", []string{"-J", "bastion", "host"}, Connection{Host: "host"}},
		{"forward specs skipped", []string{"-L", "8080:localhost:80", "-R", "9090:localhost:90", "host"}, Connection{Host: "host"}},
		{"many valued flags", []string{"-F", "cfg", "-i", "key", "-p", "2200", "user@host"}, Connection{User: "user", Host: "host", Port: "2200"}},
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
