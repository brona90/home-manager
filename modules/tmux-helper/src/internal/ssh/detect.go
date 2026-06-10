package ssh

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// execTimeout bounds the `ssh -G` call so a hung resolver/config include
// can't freeze the tmux status bar.
const execTimeout = 2 * time.Second

type Connection struct {
	User string
	Host string
	Port string
}

// Detect resolves the connection target for an ssh argv. It prefers
// `ssh -G` (which applies the user's full config). If that fails and
// allowArgvFallback is true, it falls back to a best-effort argv parse;
// otherwise it returns an error ("unknown"). Callers should disallow the
// fallback when the argv was reconstructed lossily (e.g. via strings.Fields
// on a command line that visibly contained shell quoting).
func Detect(argv []string, allowArgvFallback bool) (*Connection, error) {
	if len(argv) == 0 {
		return nil, fmt.Errorf("empty ssh argv")
	}
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ssh", append([]string{"-G"}, argv...)...).Output()
	if err != nil {
		if allowArgvFallback {
			return detectFromArgv(argv), nil
		}
		return nil, fmt.Errorf("ssh -G: %w", err)
	}
	return parseSSHG(string(out)), nil
}

func parseSSHG(out string) *Connection {
	c := &Connection{}
	scan := bufio.NewScanner(strings.NewReader(out))
	for scan.Scan() {
		line := strings.TrimSpace(scan.Text())
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, " ", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.ToLower(parts[0])
		val := strings.TrimSpace(parts[1])
		switch key {
		case "user":
			c.User = val
		case "hostname":
			c.Host = val
		case "port":
			c.Port = val
		}
	}
	return c
}

// valuedFlags are the standard ssh flags that consume the following argv
// element. Without this list, `ssh -i key host` would report "key" as the
// host.
var valuedFlags = map[string]bool{
	"-B": true, "-b": true, "-c": true, "-D": true, "-E": true,
	"-e": true, "-F": true, "-i": true, "-J": true, "-L": true,
	"-l": true, "-m": true, "-o": true, "-p": true, "-R": true,
	"-W": true,
}

func detectFromArgv(argv []string) *Connection {
	c := &Connection{}
	skipNext := false
	for i, a := range argv {
		if skipNext {
			skipNext = false
			continue
		}
		if strings.HasPrefix(a, "-") {
			if valuedFlags[a] && i+1 < len(argv) {
				switch a {
				case "-p":
					c.Port = argv[i+1]
				case "-l":
					c.User = argv[i+1]
				}
				skipNext = true
			}
			continue
		}
		if c.Host == "" {
			if at := strings.IndexByte(a, '@'); at >= 0 {
				c.User = a[:at]
				c.Host = a[at+1:]
			} else {
				c.Host = a
			}
		}
	}
	return c
}
