# specflow (on-demand multi-agent dev system)

`specflow` is a reusable multi-agent development workflow you can install into any repo: a
plan → build → spec-review → test → PR-review pipeline across 5 subagents, with a frozen
**Spec Packet** (`.claude/state/spec-packet.md`) as the single source of truth and
deterministic **hooks** that block dangerous DB/git actions. Heavy process is opt-in
(`/large-change`, `/iterate`); small edits stay friction-free.

- **Definition (do not regenerate from memory):** command `~/.claude/commands/specflow.md`;
  canonical files `~/.claude/templates/specflow/`. Both are materialised by home-manager
  (`modules/claude-specflow.nix`); edit the module + bundle there, not the live files.
- **How to invoke:** the `/specflow` slash command, OR when the user explicitly asks to
  "use / set up / install specflow" (in those words or clearly equivalent). It scaffolds the
  template into the current repo and walks through the 3 project-specific config values.
- **Trigger discipline:** run it ONLY when the user explicitly asks. Never install specflow,
  its agents, hooks, or commands into a repo on your own initiative.