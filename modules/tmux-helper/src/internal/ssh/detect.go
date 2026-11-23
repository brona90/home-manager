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

// valuedFlags are the ssh option letters that take a value, from the getopt
// string in OpenSSH's ssh.c. Without them, `ssh -i key host` would report
// "key" as the host. -P (tag) takes a value from OpenSSH 9.3 on; 9.2 accepted
// it as a no-op, and the newer meaning is the one going forward.
const valuedFlags = "BbcDEeFIiJLlmOoPpQRSWw"

// detectFromArgv is the best-effort parse used when `ssh -G` cannot run. It
// follows what OpenSSH itself does, each rule checked against `ssh -G`:
//
//   - getopt syntax: flags bundle (-vp 2222) and values attach (-p2222).
//   - Options are parsed again after the destination (`host -p 2222`), but
//     the first non-option after it begins the remote command, so the -l in
//     `ssh host ls -l foo` is not a login name. `--` ends options outright.
//   - user@host splits at the LAST @ (a@b@host is user "a@b").
//   - ssh://[user@]host[:port] is a destination too.
//   - -o Port/User/HostName count, with "=" or whitespace as separator.
//   - For user, port and hostname alike, the first value in argv order wins,
//     whichever of -l / -p / -o / the destination supplied it.
func detectFromArgv(argv []string) *Connection {
	var user, port, hostname, dest string
	first := func(dst *string, v string) {
		if *dst == "" {
			*dst = v
		}
	}
	setDest := func(d string) {
		u, h, p := splitDestination(d)
		first(&user, u)
		first(&port, p)
		dest = h
	}

	args := argv
	for len(args) > 0 {
		a := args[0]
		args = args[1:]
		if a == "--" {
			if dest == "" && len(args) > 0 {
				setDest(args[0])
			}
			break
		}
		if len(a) < 2 || a[0] != '-' {
			if dest != "" {
				break // the remote command
			}
			setDest(a)
			continue
		}
		for j := 1; j < len(a); j++ {
			if !strings.ContainsRune(valuedFlags, rune(a[j])) {
				continue // a no-value flag such as -v, -4, -A
			}
			val := a[j+1:]
			if val == "" {
				if len(args) == 0 {
					break // value missing; ssh itself would refuse
				}
				val, args = args[0], args[1:]
			}
			switch a[j] {
			case 'p':
				first(&port, val)
			case 'l':
				first(&user, val)
			case 'o':
				key, v := splitOption(val)
				switch strings.ToLower(key) {
				case "port":
					first(&port, v)
				case "user":
					first(&user, v)
				case "hostname":
					first(&hostname, v)
				}
			}
			break // the value consumed the rest of this argument
		}
	}
	if hostname == "" {
		hostname = dest
	}
	return &Connection{User: user, Host: hostname, Port: port}
}

// splitDestination splits "[user@]host" or "ssh://[user@]host[:port]".
func splitDestination(d string) (user, host, port string) {
	rest, isURI := strings.CutPrefix(d, "ssh://")
	if at := strings.LastIndexByte(rest, '@'); at >= 0 {
		user, rest = rest[:at], rest[at+1:]
	}
	if !isURI {
		return user, rest, "" // host:port is not a port outside a URI
	}
	rest, _, _ = strings.Cut(rest, "/")
	if strings.HasPrefix(rest, "[") {
		if end := strings.IndexByte(rest, ']'); end >= 0 {
			host, rest = rest[1:end], rest[end+1:]
			if p, ok := strings.CutPrefix(rest, ":"); ok {
				port = p
			}
			return user, host, port
		}
	}
	if colon := strings.LastIndexByte(rest, ':'); colon >= 0 {
		return user, rest[:colon], rest[colon+1:]
	}
	return user, rest, ""
}

// splitOption splits an -o argument the way ssh_config does: the keyword
// ends at whitespace or "=", and at most one "=" may sit among the spaces
// before the value.
func splitOption(o string) (key, val string) {
	o = strings.TrimSpace(o)
	end := strings.IndexAny(o, " \t=")
	if end < 0 {
		return o, ""
	}
	key, val = o[:end], strings.TrimLeft(o[end:], " \t")
	val = strings.TrimLeft(strings.TrimPrefix(val, "="), " \t")
	return key, val
}
