#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp[cli]>=1.2.0", "httpx>=0.27.0"]
# ///
"""Re-embed the whole graph under a new embedding model / dimensionality.

Switching embedding models changes the vector size, and Qdrant fixes vector size per
collection — so this exports all entities + documents, recreates the collections at the
new dimension, and re-embeds everything. Relations carry no real vectors, so they are
preserved as-is.

Usage:
  EMBED_MODEL=mxbai-embed-large EMBED_DIM=1024 uv run reembed.py
  (pull the model first:  ollama pull mxbai-embed-large)
"""
import sys

import kg_server as kg


def main() -> int:
    print(f"Target model: {kg.EMBED_MODEL}  dim={kg.EMBED_DIM}")
    kg._ensure_collections()

    # 1. export entities (payloads) and documents (payloads)
    entities = kg._scroll(kg.ENTITIES, None)
    docs = kg._scroll(kg.DOCUMENTS, None)
    print(f"Exporting {len(entities)} entities, {len(docs)} document chunks…")

    # 2. drop and recreate entity + document collections at the new dim
    for c in (kg.ENTITIES, kg.DOCUMENTS):
        kg._q("DELETE", f"/collections/{c}")
    kg._init_done = False
    kg._ensure_collections()

    # 3. re-embed and re-store entities (observations already normalized on read)
    for p in entities:
        kg._store_entity(p["name"], p.get("type", "unknown"), kg._coerce_obs(p.get("observations", [])))
    # 4. re-embed document chunks
    for d in docs:
        vec = kg._embed(d["text"], "document")
        kg._q("PUT", f"/collections/{kg.DOCUMENTS}/points?wait=true",
              json={"points": [{"id": str(kg.uuid.uuid5(kg.NS, f"doc:{d['doc'].lower()}:{d['chunk']}")),
                                "vector": vec, "payload": d}]})

    print("Done. New stats:", kg.kg_stats())
    print("NOTE: also set EMBED_DIM permanently — export it for the MCP server, or change "
          "the default in kg_server.py — so future runs use the right size.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
