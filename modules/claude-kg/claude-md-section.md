# Shared knowledge graph (claude-kg)

A persistent, local knowledge graph is available to every session via the `claude-kg`
MCP server (Qdrant vector DB + local Ollama embeddings, fully offline). Use it as
shared long-term memory across Claude instances.

**Tools:** `kg_recall` (hybrid semantic + graph recall — start here), `kg_search`
(plain semantic recall), `kg_get`, `kg_neighbors` (graph traversal), `kg_upsert_entity`,
`kg_add_observations` (both take an optional `source` for provenance; observations are
auto-timestamped), `kg_relate`, `kg_merge` + `kg_find_duplicates` (dedupe entities),
`kg_ingest_document` + `kg_search_documents` (RAG over free text), `kg_delete_entity`,
`kg_stats`. A terminal CLI (`kg <cmd>`) exposes the same operations outside Claude.

**When to read:** at the start of a non-trivial task, call `kg_recall` with the topic
to recall what's already known (and how it connects) before asking the user or
re-deriving facts. (A SessionStart hook also injects a graph summary + repo-seeded
recall, and a UserPromptSubmit hook injects per-prompt recall — but still call
`kg_recall` yourself for anything those digests don't already cover.)

**When to write:** when you learn a durable, reusable fact (a project's purpose, a
decision and its rationale, how systems connect, a user preference). Record it as an
entity with `observations`, and link related entities with `kg_relate`. Don't store
secrets, transient state, or anything already in the repo/git history.

Infra lives at `~/claude-kg/` (see its README to start/stop the DB).