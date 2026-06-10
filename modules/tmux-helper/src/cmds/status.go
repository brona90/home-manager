package cmds

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"

	"tmux-helper/internal/ssh"
	"tmux-helper/internal/system"
	"tmux-helper/internal/theme"
)

// Status routes the 'status' subcommand.
func Status(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: status <uptime-fmt|user-host|git-branch|nix-shell|llm|battery> [args...]")
	}
	switch args[0] {
	case "uptime-fmt":
		return statusUptimeFmt()
	case "user-host":
		return statusUserHost(args[1:])
	case "git-branch":
		return statusGitBranch(args[1:])
	case "nix-shell":
		return statusNixShell()
	case "llm":
		return statusLLM(args[1:])
	case "battery":
		return statusBattery()
	default:
		return fmt.Errorf("unknown status subcommand: %s", args[0])
	}
}

func statusUptimeFmt() error {
	d, err := system.Uptime()
	if err != nil {
		return err
	}
	fmt.Println(system.FormatUptimeShort(d))
	return nil
}

// statusUserHost: when invoked with `pane_id pane_pid [server_pid]`, walks
// the pane's process tree for ssh/mosh and emits user@host[:port]. Falls back
// to local user@host if no ssh chain is found or args are missing. The third
// arg is #{pid} (the tmux server pid) from the status format, used as a
// stable cache key.
func statusUserHost(args []string) error {
	if len(args) >= 2 {
		serverPIDArg := ""
		if len(args) >= 3 {
			serverPIDArg = args[2]
		}
		if conn := detectPaneSSH(args[0], args[1], serverPIDArg); conn != nil {
			u := conn.User
			if u == "" {
				u = localUser()
			}
			if conn.Port != "" && conn.Port != "22" {
				fmt.Printf("%s@%s:%s\n", u, conn.Host, conn.Port)
			} else {
				fmt.Printf("%s@%s\n", u, conn.Host)
			}
			return nil
		}
	}
	host, _ := os.Hostname()
	fmt.Printf("%s@%s\n", localUser(), host)
	return nil
}

func localUser() string {
	if u, err := user.Current(); err == nil {
		return u.Username
	}
	return "user"
}

// detectPaneSSH returns the ssh connection a pane is currently on, or nil
// if the pane is local. Uses a 30s file cache keyed by (server_pid, pane_id).
func detectPaneSSH(paneID, panePIDStr, serverPIDStr string) *ssh.Connection {
	serverPID := resolveServerPID(serverPIDStr)
	if cached, hit := ssh.Read(serverPID, paneID); hit {
		return cached
	}
	panePID, err := strconv.Atoi(panePIDStr)
	if err != nil {
		return nil
	}
	tree, err := system.PsTree()
	if err != nil {
		return nil
	}
	sshPID := system.FindSSH(tree, panePID)
	if sshPID == 0 {
		_ = ssh.Write(serverPID, paneID, nil)
		return nil
	}
	argsStr, err := system.ProcessArgs(sshPID)
	if err != nil || argsStr == "" {
		// Negative-cache so a flaky/hung ps doesn't trigger a full re-walk
		// on every status refresh.
		_ = ssh.Write(serverPID, paneID, nil)
		return nil
	}
	parts := strings.Fields(argsStr)
	if len(parts) < 2 {
		_ = ssh.Write(serverPID, paneID, nil)
		return nil
	}
	// strings.Fields flattens shell quoting; if the command line visibly
	// contained quotes/escapes, the reconstructed argv is unreliable, so
	// don't let ssh.Detect fall back to guessing the host from it.
	argvReliable := !strings.ContainsAny(argsStr, `'"\`)
	conn, err := ssh.Detect(parts[1:], argvReliable)
	if err != nil {
		_ = ssh.Write(serverPID, paneID, nil)
		return nil
	}
	_ = ssh.Write(serverPID, paneID, conn)
	return conn
}

// resolveServerPID turns the #{pid} format arg into the tmux server pid.
// When the arg is missing/garbled (older format string still cached on the
// server), fall back to asking tmux directly, and only then to Getppid()
// (which equals the server pid only while `sh -c` exec-optimizes).
func resolveServerPID(arg string) int {
	if pid, err := strconv.Atoi(strings.TrimSpace(arg)); err == nil && pid > 0 {
		return pid
	}
	ctx, cancel := context.WithTimeout(context.Background(), system.ExecTimeout)
	defer cancel()
	if out, err := exec.CommandContext(ctx, "tmux", "display-message", "-p", "#{pid}").Output(); err == nil {
		if pid, err := strconv.Atoi(strings.TrimSpace(string(out))); err == nil && pid > 0 {
			return pid
		}
	}
	return os.Getppid()
}

// statusGitBranch emits the current git branch when the pane's cwd is in a
// git repo, prefixed with " " and a leading symbol. Empty when not in a
// repo (so #{...} substitutions render blank). Cwd is passed as arg[0],
// typically #{pane_current_path} from the bind.
func statusGitBranch(args []string) error {
	if len(args) == 0 {
		return nil
	}
	cwd := args[0]
	if cwd == "" {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), system.ExecTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD")
	out, err := cmd.Output()
	if err != nil {
		return nil // Not a repo, or git missing -- silently empty.
	}
	branch := strings.TrimSpace(string(out))
	if branch == "" || branch == "HEAD" {
		return nil
	}
	fmt.Printf(" %s", branch)
	return nil
}

// statusNixShell shows " ❄" when IN_NIX_SHELL is set in the helper's env.
// In practice this picks up nix-shell, nix develop, devenv -- anything
// that exports IN_NIX_SHELL. Helper's env comes from the tmux client/pane
// that invoked it via #(...) substitution.
func statusNixShell() error {
	if os.Getenv("IN_NIX_SHELL") != "" {
		fmt.Print(" ❄")
	}
	return nil
}

// llmNames are the LLM tool process names that light up the 🤖 indicator.
var llmNames = []string{"claude", "aider", "cursor", "copilot", "ollama"}

// llmNameFromComm normalizes a ps comm value and returns the matching LLM
// tool name, or "" if none.
//
// On darwin `ps -o comm=` prints the full executable path, so take the
// basename FIRST. Then accommodate Nix-wrapped binaries: a Nix-wrapped
// `claude` shows up as ".claude-wrapped" (or "/nix/store/.../.claude-wrapped"
// on darwin) -- strip the leading "." and trailing "-wrapped" before checking
// against the known list. Prefix match catches "claude-code",
// "ollama-server", etc.
func llmNameFromComm(comm string) string {
	c := filepath.Base(strings.ToLower(comm))
	c = strings.TrimPrefix(c, ".")
	c = strings.TrimSuffix(c, "-wrapped")
	for _, name := range llmNames {
		if c == name || strings.HasPrefix(c, name+"-") {
			return name
		}
	}
	return ""
}

// statusLLM walks the pane's process tree (arg[0] = #{pane_pid}) and emits
// an indicator when claude/aider/cursor/copilot/ollama is in the chain.
func statusLLM(args []string) error {
	if len(args) == 0 {
		return nil
	}
	panePID, err := strconv.Atoi(args[0])
	if err != nil {
		return nil
	}
	tree, err := system.PsTree()
	if err != nil {
		return nil
	}
	for _, pid := range system.DescendantsOf(tree, panePID) {
		if name := llmNameFromComm(tree[pid].Comm); name != "" {
			fmt.Printf(" 🤖 %s", name)
			return nil
		}
	}
	return nil
}

// fallbackBatteryGradient is used when the active theme can't be resolved
// (themes JSON unreadable, or unknown theme name in @tmux_theme_preset).
// Matches the gpakosz default red→orange→yellow→green spectrum.
var fallbackBatteryGradient = theme.Interpolate10([4]string{
	"#ff0000", "#ffaf00", "#afff00", "#00ff00",
})

// statusBattery prints a 10-cell heart bar followed by NN% when a battery
// is present on the host running the tmux server. Cells 0..(charge/10)-1
// render as colored hearts using the active theme's batteryGradient
// (4 anchors interpolated to 10 cells); remaining cells render as a dim
// "·". A charging indicator (🔌 fully charged, ⚡ charging, 🪫 low)
// prefixes the bar. Empty output on desktops, WSL, and headless servers.
func statusBattery() error {
	b, err := system.ReadBattery()
	if err != nil || !b.Present {
		return nil
	}

	// Round-half-up to the nearest 10% bucket, clamped to [0, 10].
	cells := (b.Percent + 5) / 10
	if cells < 0 {
		cells = 0
	}
	if cells > 10 {
		cells = 10
	}

	gradient := fallbackBatteryGradient
	if themes, err := loadThemes(); err == nil {
		name := strings.TrimSpace(maybeOpt(optThemePreset))
		if name == "" {
			if names := themes.Names(); len(names) > 0 {
				name = names[0]
			}
		}
		// pal.BatteryGradient may be the zero value (four empty strings) if
		// the themes JSON pre-dates the field -- happens when the helper is
		// run with TMUX_HELPER_THEMES still pointing at an older generation.
		// Treat empty as "use the global fallback" rather than rendering
		// 10 #000000 hearts (which all snap to xterm colour16, looking
		// uniformly black/grey).
		if pal, ok := themes[name]; ok && pal.BatteryGradient[0] != "" {
			gradient = theme.Interpolate10(pal.BatteryGradient)
		}
	}

	prefix := ""
	switch {
	case b.Charging && b.Percent >= 99:
		prefix = "🔌 "
	case b.Charging:
		prefix = "⚡ "
	case b.Percent <= 20:
		prefix = "🪫 "
	}

	var bar strings.Builder
	bar.WriteString(" ")
	bar.WriteString(prefix)
	for i := 0; i < 10; i++ {
		if i < cells {
			fmt.Fprintf(&bar, "#[fg=colour%d]♥", theme.HexTo256(gradient[i]))
		} else {
			bar.WriteString("#[fg=default]·")
		}
	}
	bar.WriteString("#[default] ")
	fmt.Fprintf(&bar, "%d%%", b.Percent)
	fmt.Print(bar.String())
	return nil
}
