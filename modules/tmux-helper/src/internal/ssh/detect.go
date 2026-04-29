package ssh

import (
	"bufio"
	"fmt"
	"os/exec"
	"strings"
)

type Connection struct {
	User string
	Host string
	Port string
}

func Detect(argv []string) (*Connection, error) {
	if len(argv) == 0 {
		return nil, fmt.Errorf("empty ssh argv")
	}
	out, err := exec.Command("ssh", append([]string{"-G"}, argv...)...).Output()
	if err != nil {
		return detectFromArgv(argv), nil
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

func detectFromArgv(argv []string) *Connection {
	c := &Connection{}
	skipNext := false
	for i, a := range argv {
		if skipNext {
			skipNext = false
			continue
		}
		if a == "-p" && i+1 < len(argv) {
			c.Port = argv[i+1]
			skipNext = true
			continue
		}
		if strings.HasPrefix(a, "-") {
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
