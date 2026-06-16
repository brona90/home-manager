#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "mcp[cli]>=1.2.0",
#   "httpx>=0.27.0",
# ]
# ///
"""End-to-end smoke test for claude-kg. Run, inspect output, then it cleans up.

Uses a dedicated 'smoke:' name prefix so it can NEVER touch real seeded data.
"""
import kg_server as kg

A, B, C = "smoke:project", "smoke:Qdrant", "smoke:Brona"

print("stats (before):", kg.kg_stats())
print(kg.kg_upsert_entity(A, "project",
      ["A local knowledge-graph MCP server.", "Backed by Qdrant and Ollama embeddings."],
      source="smoke-test"))
print(kg.kg_upsert_entity(B, "tool", ["Open-source vector database written in Rust."]))
print(kg.kg_add_observations(A, ["Runs fully offline with no API costs."], source="smoke-test"))
print(kg.kg_relate(A, "uses", B))
print(kg.kg_relate(C, "owns", A))

print("\nsearch 'vector database':")
for h in kg.kg_search("which vector database does this use", limit=3):
    print("  ", h["name"], h["score"], h["type"])

print("\nget A:", kg.kg_get(A))
print("\nneighbors of B depth=2:", kg.kg_neighbors(B, depth=2))

# cleanup so the test leaves no residue
for n in (A, B, C):
    kg.kg_delete_entity(n)
print("\ncleaned up. final stats:", kg.kg_stats())
