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

// TestDetectFromArgvMatchesOpenSSH: every expectation here is what
// `ssh -G -F /dev/null <argv>` printed on OpenSSH 9.2p1, except that ssh's
// defaults (the local user, port 22) appear as "" -- the fallback reports
// only what argv says. Most are cases the old parser got wrong.
func TestDetectFromArgvMatchesOpenSSH(t *testing.T) {
	tests := []struct {
		name string
		argv []string
		want Connection
	}{
		{"bundled flags", []string{"-vp", "2222", "host"}, Connection{Host: "host", Port: "2222"}},
		{"long bundle", []string{"-46Ap", "2200", "host"}, Connection{Host: "host", Port: "2200"}},
		{"attached port", []string{"-p2222", "host"}, Connection{Host: "host", Port: "2222"}},
		{"attached login", []string{"-lalice", "host"}, Connection{User: "alice", Host: "host"}},
		{"options after host", []string{"host", "-p", "2222"}, Connection{Host: "host", Port: "2222"}},
		{"login after host", []string{"host", "-l", "alice"}, Connection{User: "alice", Host: "host"}},
		{"remote command flags", []string{"host", "ls", "-l", "foo"}, Connection{Host: "host"}},
		{"double dash after host", []string{"host", "--", "ls", "-p", "9"}, Connection{Host: "host"}},
		{"double dash before host", []string{"--", "host", "-p", "2"}, Connection{Host: "host"}},
		{"control path value", []string{"-S", "/tmp/ctl", "host"}, Connection{Host: "host"}},
		{"control command value", []string{"-O", "check", "host"}, Connection{Host: "host"}},
		{"pkcs11 value", []string{"-I", "lib", "host"}, Connection{Host: "host"}},
		{"tunnel value", []string{"-w", "0:1", "host"}, Connection{Host: "host"}},
		{"last @ splits", []string{"a@b@host"}, Connection{User: "a@b", Host: "host"}},
		{"-l before user@ wins", []string{"-l", "alice", "bob@host"}, Connection{User: "alice", Host: "host"}},
		{"user@ before -l wins", []string{"bob@host", "-l", "alice"}, Connection{User: "bob", Host: "host"}},
		{"first -p wins", []string{"-p", "1", "-p", "2", "host"}, Connection{Host: "host", Port: "1"}},
		{"first -l wins", []string{"-l", "a", "-l", "b", "host"}, Connection{User: "a", Host: "host"}},
		{"-o Port", []string{"-o", "Port=2200", "host"}, Connection{Host: "host", Port: "2200"}},
		{"-o before -p wins", []string{"-o", "Port=5", "-p", "6", "host"}, Connection{Host: "host", Port: "5"}},
		{"-p before -o wins", []string{"-p", "6", "-o", "Port=5", "host"}, Connection{Host: "host", Port: "6"}},
		{"-o attached User", []string{"-oUser=alice", "host"}, Connection{User: "alice", Host: "host"}},
		{"-o space separator", []string{"-o", "User alice", "host"}, Connection{User: "alice", Host: "host"}},
		{"-o spaced equals", []string{"-o", "port = 2203", "host"}, Connection{Host: "host", Port: "2203"}},
		{"-o HostName", []string{"host", "-o", "HostName=real"}, Connection{Host: "real"}},
		{"first HostName wins", []string{"-o", "Hostname=r1", "-o", "HostName=r2", "host"}, Connection{Host: "r1"}},
		{"uri", []string{"ssh://alice@host:2200"}, Connection{User: "alice", Host: "host", Port: "2200"}},
		{"uri host only", []string{"ssh://host"}, Connection{Host: "host"}},
		{"uri port beats later -p", []string{"ssh://a@host:7", "-p", "8"}, Connection{User: "a", Host: "host", Port: "7"}},
		{"-p beats later uri port", []string{"-p", "8", "ssh://a@host:7"}, Connection{User: "a", Host: "host", Port: "8"}},
		{"-l beats later uri user", []string{"-l", "b", "ssh://a@host:7"}, Connection{User: "b", Host: "host", Port: "7"}},
		{"host:port is not a port", []string{"host:2200"}, Connection{Host: "host:2200"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := detectFromArgv(tt.argv); *got != tt.want {
				t.Errorf("detectFromArgv(%q) = %+v, want %+v", tt.argv, *got, tt.want)
			}
		})
	}
}
