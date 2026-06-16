# claude-kg

A local, offline knowledge-graph "shared memory" for every Claude Code session on this
machine, plus auto-capture of durable facts at session end. Managed declaratively here;
enabled via `my.claudeKg.enable` (set on the WSL host).

## Pieces

- **`package.nix`** — builds a pure `python3.withPackages [mcp httpx]` env (no `uv`) and
  installs to `$PATH`:
  - `kg-server` — the MCP server (entities/relations/documents over Qdrant).
  - `kg` — terminal CLI (`kg stats|recall|search|get|list|add|relate|dupes|merge|delete`).
  - `kg-capture` — local-model fact extractor (Ollama).
  - `kg-capture-hook` — the SessionEnd hook (local backend by default).
  - `kg-snapshot` — Qdrant snapshot + prune (run by the timer).
  - `kg-seed`, `kg-reembed` — maintenance helpers.
- **`default.nix`** — the module:
  - registers `kg-server` via `my.claudeCode.mcpServers.claude-kg` and the capture hook
    via `my.claudeCode.sessionEndCommands` (merged into `~/.claude.json` by claude-code).
  - runs **Qdrant** as a `systemd --user` service (`qdrant.service`).
  - runs a daily snapshot via `kg-snapshot.service` + `.timer` (03:17).
- **`src/`** — the Python/shell sources.

## Runtime layout (not in the nix store — mutable state)

- `~/.local/share/claude-kg/qdrant` — Qdrant storage (the graph).
- `~/.local/share/claude-kg/snapshots` — snapshots.
- `~/.local/share/claude-kg/{capture,snapshot}.log` — logs.

## Dependencies

- Docker (system daemon) — Qdrant container.
- Ollama on `:11434` with `nomic-embed-text` (embeddings) and `qwen2.5:7b` (local
  capture). These are not nix-managed; install/pull separately.

## Operating

```bash
systemctl --user status qdrant kg-snapshot.timer
systemctl --user restart qdrant
kg stats
journalctl --user -u qdrant -f
tail -f ~/.local/share/claude-kg/capture.log
```

Capture backend: `CLAUDE_KG_CAPTURE_BACKEND=local` (default, free, local Ollama) or
`claude` (headless Claude, higher quality, costs tokens).
