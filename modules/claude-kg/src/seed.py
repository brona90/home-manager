#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp[cli]>=1.2.0", "httpx>=0.27.0"]
# ///
"""Seed claude-kg with foundational facts about itself. Safe to re-run (upserts)."""
import kg_server as kg

kg.kg_upsert_entity("claude-kg", "project", [
    "Local knowledge-graph MCP server providing shared long-term memory for all Claude Code instances on this machine.",
    "Lives at ~/claude-kg. Vector store is Qdrant in Docker on port 6333; embeddings via local Ollama nomic-embed-text.",
    "Start/stop with `docker compose up -d` / `down` in ~/claude-kg. Data persists in ~/claude-kg/qdrant_storage.",
])
kg.kg_upsert_entity("Qdrant", "tool",
    ["Open-source vector database (Rust). Runs as the claude-kg-qdrant Docker container on port 6333."])
kg.kg_upsert_entity("Ollama", "tool",
    ["Local model runner on port 11434. Serves the nomic-embed-text embedding model (768-dim) for claude-kg."])
kg.kg_upsert_entity("Brona", "person", [
    "Owner of this machine. Email brona90@gmail.com.",
    "Requested a free local vector DB + knowledge graph to give Claude instances shared memory.",
])
kg.kg_relate("claude-kg", "uses", "Qdrant")
kg.kg_relate("claude-kg", "uses", "Ollama")
kg.kg_relate("Brona", "owns", "claude-kg")

print("seeded:", kg.kg_stats())
print("recall test:", [h["name"] for h in kg.kg_search("how do Claude instances share memory", limit=3)])
