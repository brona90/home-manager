# claude-kg

A local, offline knowledge-graph "shared memory" for every Claude Code session on this
machine, plus auto-capture of durable facts at session end. Managed declaratively here;
enabled via `my.claudeKg.enable` (set on the WSL host). The module also takes
`my.claudeKg.image` (default `qdrant/qdrant:latest`) and `my.claudeKg.dockerBin`
(default `/usr/bin/docker`).

## Pieces

- **`package.nix`** — builds a pure `python3.withPackages [mcp httpx]` env (no `uv`) and
  installs to `$PATH`:
  - `kg-server` — the MCP server (entities/relations/documents over Qdrant).
  - `kg` — terminal CLI (`kg stats|recall|search|docs|get|list|add|relate|dupes|merge|delete|forget`).
  - `kg-capture` — local-model fact extractor (Ollama).
  - `kg-capture-hook` — the SessionEnd hook (local backend by default).
  - `kg-snapshot` — Qdrant snapshot + prune (run by the timer).
  - `kg-seed`, `kg-reembed` — maintenance helpers.
  `default.nix` additionally installs three wrappers so the hooks have stable
  `~/.nix-profile/bin` names: `kg-session-start-hook`, `kg-prompt-recall-hook`,
  and `kg-capture-hook-win` — the last exists because Claude Code on Windows
  hands the hook a `C:\...` transcript path.
- **`claude-md-section.md`** — the text merged into `~/.claude/CLAUDE.md`, so every
  session is told the graph exists and how to reach it.
- **`default.nix`** — the module:
  - registers `kg-server` via `my.claudeCode.mcpServers.claude-kg`, and wires all four
    Claude Code surfaces (merged into `~/.claude.json` by claude-code):
    `sessionEndCommands` → `kg-capture-hook` (the write side),
    `sessionStartCommands` → `kg-session-start-hook` (timeout 45),
    `userPromptSubmitCommands` → `kg-prompt-recall-hook` (timeout 60), and
    `claudeMdSections` from `claude-md-section.md`. The last two are the READ side:
    they are why prior memory shows up in a session without anyone asking for it.
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

## Retraction (changing your mind)

Capture is **append-only** — `kg_add_observations` never removes facts, so a reversed
decision leaves the old observation alongside the new one (the newer timestamp wins on
recall, but the stale fact can still surface). To actually retract:

```bash
kg forget "<entity>" "<substring>" ["<substring2>" ...]   # drop matching observations, re-embed
kg delete "<entity>"                                       # remove the whole entity + edges
```

`kg forget` keeps the entity and re-embeds it from the surviving observations, so recall
stops returning the dropped facts. Matching is case-insensitive substring. There is no
automatic contradiction detection in the capture hook — retraction is deliberate.
