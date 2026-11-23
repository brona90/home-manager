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

This DELETEs two collections, so nothing is deleted until three things hold:
  1. a Qdrant snapshot of each collection was created (server-side restore point);
  2. the full export was written to disk (client-side restore point);
  3. the exported point count equals Qdrant's exact count for each collection.
An earlier version exported only the first scroll page (1000 points) and then
deleted everything, permanently losing the rest.

Usage:
  EMBED_MODEL=mxbai-embed-large EMBED_DIM=1024 uv run reembed.py
  (pull the model first:  ollama pull mxbai-embed-large)
"""
import json
import os
import sys
import time

import kg_server as kg


def _count(collection: str) -> int:
    return kg._q("POST", f"/collections/{collection}/points/count",
                 json={"exact": True})["result"]["count"]


def _export_dir() -> str:
    base = os.environ.get("CLAUDE_KG_DATA_DIR",
                          os.path.expanduser("~/.local/share/claude-kg"))
    path = os.path.join(base, "reembed-exports", time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def export_or_abort(collections: tuple[str, ...], out_dir: str) -> dict[str, list[dict]]:
    """Snapshot, export and count-check every collection. Raise before any delete."""
    exported: dict[str, list[dict]] = {}
    for c in collections:
        snap = kg._q("POST", f"/collections/{c}/snapshots?wait=true")
        name = (snap.get("result") or {}).get("name")
        if not name:
            raise RuntimeError(f"snapshot of {c} returned no name: {snap!r}")
        print(f"  snapshot {c}: {name}")

        points = kg._scroll(c, None)
        expected = _count(c)
        if len(points) != expected:
            raise RuntimeError(f"{c}: exported {len(points)} points but Qdrant holds {expected}")

        path = os.path.join(out_dir, f"{c}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(points, f)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(path, 0o600)
        print(f"  export   {c}: {len(points)} points -> {path}")
        exported[c] = points
    return exported


def main() -> int:
    print(f"Target model: {kg.EMBED_MODEL}  dim={kg.EMBED_DIM}")
    kg._ensure_collections()

    # 1. snapshot + export + verify, before anything is deleted
    out_dir = _export_dir()
    try:
        exported = export_or_abort((kg.ENTITIES, kg.DOCUMENTS), out_dir)
    except Exception as e:  # noqa: BLE001 -- any failure here must stop the delete
        print(f"ABORTED before deleting anything: {e}", file=sys.stderr)
        return 1
    entities, docs = exported[kg.ENTITIES], exported[kg.DOCUMENTS]

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

    # 5. the rebuilt collections must hold what was exported
    rc = 0
    for c, want in ((kg.ENTITIES, len(entities)), (kg.DOCUMENTS, len(docs))):
        got = _count(c)
        if got != want:
            print(f"WARNING: {c} holds {got} points after re-embed, expected {want}; "
                  f"export is at {out_dir}", file=sys.stderr)
            rc = 1

    print("Done. New stats:", kg.kg_stats())
    print("NOTE: also set EMBED_DIM permanently — export it for the MCP server, or change "
          "the default in kg_server.py — so future runs use the right size.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
