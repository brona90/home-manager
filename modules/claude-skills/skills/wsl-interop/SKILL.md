---
name: wsl-interop
description: Reaching the Debian WSL filesystem and services from Windows-native Claude Code without hanging or corrupting things. Use this skill whenever a task involves a path under /home/gfoster or \\wsl.localhost, running a Linux command from a Windows session, registering or debugging an MCP server that lives in WSL, a hook that crosses the boundary, or anything in the home-manager / orrery / org repos while the session's working directory is C:\Users\brona. Reach for it as soon as a shell command is slow or a UNC path is involved, rather than after the timeout.
---

# Crossing the Windows/WSL boundary

Claude Code runs natively on Windows here, while nearly all of the actual work
(home-manager, orrery, org, the MCP servers) lives in the Debian WSL distro.
Those are two different machines sharing a filesystem bridge, and the bridge is
the slow part.

## Run Linux commands through wsl.exe, not through UNC paths

Shelling into the distro is fast. Walking the 9P filesystem bridge from git-bash
is not — recursive listings and `find` over `\\wsl.localhost\...` routinely take
minutes and hit the tool timeout.

```sh
wsl.exe -d Debian -- bash -lc 'cd ~/orrery && make verify'
```

- `bash -lc` gives a login shell, so Nix profile binaries and aliases resolve.
- Use `-e <binary>` instead when stdio cleanliness matters (MCP servers): it runs
  no login shell, so no banner noise corrupts the protocol.

### Shell variables do not survive the crossing

This is the trap that costs the most time, because it fails silently — the
variable expands to empty and the command runs anyway, against the wrong path:

```sh
$ wsl.exe -d Debian -- bash -lc 'x=hello; echo "got:[$x]"'
got:[]
```

Single quotes do not protect it; the MSYS layer reprocesses the argument on its
way to a Windows `.exe`. The visible symptoms are a `mkdir` that creates
`/skills` instead of `$dst/skills`, or a loop whose body runs the right number
of times with an empty variable.

Two reliable routes:

- **Keep `wsl.exe` invocations variable-free.** Repeat the literal path in each
  command rather than binding it once. Verbose, but it works.
- **Write the script to a file and execute that.** A heredoc into
  `$CLAUDE_JOB_DIR/tmp`, then `wsl.exe -d Debian -- bash /path/to/script.sh`.
  Variables inside the file are safe because nothing reprocesses it.

`MSYS_NO_PATHCONV=1` fixes *path* mangling (a bare `/mnt/c/...` argument being
rewritten) but does **not** fix variable stripping — they are separate problems
and the first is often mistaken for the second.

For file operations in either direction, the PowerShell tool is the better
instrument: it handles variables normally and reads `\\wsl.localhost\Debian\...`
directly.

```powershell
Copy-Item -Recurse -Force -Path "\\wsl.localhost\Debian\home\gfoster\src\*" -Destination "C:\dest\"
```

The Read and Write tools *do* work fine on `\\wsl.localhost\Debian\home\...`
paths — it is directory traversal and process spawning that are slow. Reading
and writing known paths that way is fine and often clearer.

## Which config is in play

Both sides have a `~/.claude`, and they are not the same file.

| | WSL `/home/gfoster/.claude` | Windows `C:\Users\brona\.claude` |
|---|---|---|
| managed by | home-manager (`/nix/store` symlinks) | hand-maintained |
| edit via | the flake, then `hms` | edit the file directly |

A change made on one side does not reach the other. When a setting matters on
both, say so explicitly and make both — the two drifting apart is the normal
failure, not the exception. Check `attribution`, `enabledPlugins`, and hook
definitions in particular.

## MCP servers

The servers are stdio subprocesses that must run **inside** WSL — `claude-kg`
depends on Ollama listening on `127.0.0.1:11434` inside the distro, which is
unreachable from the Windows host. Register them by having Windows launch the
Linux binary:

```sh
claude mcp add claude-kg -s user -- wsl.exe -d Debian -e /home/gfoster/.nix-profile/bin/kg-server
```

Point at `~/.nix-profile/bin/` wrappers, never at the `/nix/store/<hash>/` paths
that appear in `~/.claude.json` — the hash changes on every `hms` and the
Windows config silently breaks.

The backing services do not auto-start. `wsl.exe` boots the distro but not the
containers: Qdrant (`:6333`) and SearXNG (`:8888`) need `docker compose up -d`
in `~/claude-kg` and `~/searxng`, plus Ollama on `:11434`.

## Hook timeouts

Every hook that crosses the boundary pays the interop tax. A hook measured at
under 7s natively has been observed taking 9s longer through `wsl.exe`, so
budget for the slowest caller rather than the one you measured. The home-manager
option types carry per-command timeouts for exactly this reason — a single
per-event default cannot express it.

## Related

The rule that all of this configuration is generated rather than edited is in
[nix-home-manager](../nix-home-manager/SKILL.md); read it before changing
anything under `~/.claude` on the WSL side.
