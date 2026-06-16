# searxng

A local [SearXNG](https://docs.searxng.org) metasearch engine + an MCP server giving
every Claude session private web search — no API key, no rate limits. Managed
declaratively; enabled via `my.searxng.enable` (set on the WSL host). Companion to
`../claude-kg`.

## Pieces

- **`package.nix`** — `python3.withPackages [mcp httpx]` env installing `searxng-mcp`
  on `$PATH` (exposes `web_search` and `web_news`).
- **`default.nix`** — the module:
  - registers the server via `my.claudeCode.mcpServers.searxng`
    (`SEARXNG_URL=http://localhost:<port>`).
  - runs **SearXNG** as a `systemd --user` service (`searxng.service`, Docker).
  - renders `~/.config/searxng/settings.yml` at activation from `settings.yml`,
    substituting a generated `secret_key` (kept out of the repo / nix store; reused
    across switches).
- **`settings.yml`** — settings template (`__SECRET__` placeholder).
- **`src/search_server.py`** — the MCP server.

## Operating

```bash
systemctl --user status searxng
systemctl --user restart searxng
curl -s 'localhost:8888/search?q=test&format=json' | jq '.results[0]'
```

Default host port is `8888` (`my.searxng.port`). Requires the system Docker daemon.
