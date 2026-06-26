#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "mcp[cli]>=1.2.0",
#   "httpx>=0.27.0",
# ]
# ///
"""
claude-kg: a local knowledge-graph MCP server backed by Qdrant + Ollama embeddings.

Any Claude instance configured with this server gets a shared, persistent memory:
  - entities  : named nodes with a type + timestamped, provenance-tagged observations
  - relations : directed, labeled edges between entities (graph traversal)
  - documents : chunked free text for RAG, kept separate from the curated graph

Embeddings are produced locally by Ollama (default nomic-embed-text, 768-dim) so
nothing leaves the machine and there are no API costs. Talks to Qdrant over plain
REST (httpx) to stay dependency-light and avoid native libs.

Config via env vars:
  QDRANT_URL    (default http://localhost:6333)
  OLLAMA_URL    (default http://localhost:11434)
  EMBED_MODEL   (default nomic-embed-text)
  EMBED_DIM     (default 768; must match the model — 1024 for mxbai-embed-large)
"""
from __future__ import annotations

import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

# Quiet per-request INFO logs (keeps the CLI clean and MCP stdout uncluttered).
logging.getLogger("httpx").setLevel(logging.WARNING)

QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333").rstrip("/")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434").rstrip("/")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
EMBED_DIM = int(os.environ.get("EMBED_DIM", "768"))  # nomic-embed-text=768, mxbai-embed-large=1024


def _default_prefixes(model: str) -> tuple[str, str]:
    """Task prefixes (query, document) recommended for the embedding model.

    Retrieval models embed a query and a stored passage differently; using the model's
    own convention measurably improves recall. nomic prefixes BOTH sides; mxbai prefixes
    only the query.
    """
    m = model.lower()
    if "nomic" in m:
        return "search_query: ", "search_document: "
    if "mxbai" in m:
        return "Represent this sentence for searching relevant passages: ", ""
    return "", ""


_qp, _dp = _default_prefixes(EMBED_MODEL)
QUERY_PREFIX = os.environ.get("EMBED_QUERY_PREFIX", _qp)
DOC_PREFIX = os.environ.get("EMBED_DOC_PREFIX", _dp)

ENTITIES = "entities"
RELATIONS = "relations"
DOCUMENTS = "documents"
# Deterministic namespace so the same name always maps to the same point id (=> upsert/dedupe).
NS = uuid.UUID("6e6b1f2a-0000-4000-8000-c1a0de000001")

mcp = FastMCP("claude-kg")
_http = httpx.Client(timeout=120.0)  # generous: first embed cold-loads the model (~50s)
_init_done = False


# --------------------------------------------------------------------------- #
# low-level REST helpers
# --------------------------------------------------------------------------- #
def _q(method: str, path: str, **kwargs) -> dict:
    r = _http.request(method, f"{QDRANT_URL}{path}", **kwargs)
    r.raise_for_status()
    return r.json() if r.content else {}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _ensure_collections() -> None:
    global _init_done
    if _init_done:
        return
    existing = {c["name"] for c in _q("GET", "/collections")["result"]["collections"]}
    if ENTITIES not in existing:
        _q("PUT", f"/collections/{ENTITIES}",
           json={"vectors": {"size": EMBED_DIM, "distance": "Cosine"}})
        for field in ("name", "type"):
            _q("PUT", f"/collections/{ENTITIES}/index",
               json={"field_name": field, "field_schema": "keyword"})
    if RELATIONS not in existing:
        # Edges don't need semantic search; a size-1 dummy vector satisfies Qdrant's schema.
        _q("PUT", f"/collections/{RELATIONS}",
           json={"vectors": {"size": 1, "distance": "Dot"}})
        for field in ("source", "target", "relation"):
            _q("PUT", f"/collections/{RELATIONS}/index",
               json={"field_name": field, "field_schema": "keyword"})
    if DOCUMENTS not in existing:
        _q("PUT", f"/collections/{DOCUMENTS}",
           json={"vectors": {"size": EMBED_DIM, "distance": "Cosine"}})
        _q("PUT", f"/collections/{DOCUMENTS}/index",
           json={"field_name": "doc", "field_schema": "keyword"})
    _init_done = True


def _embed(text: str, kind: str = "query") -> list[float]:
    # Apply the model's task prefix; `kind` is "query" for searches, "document" for
    # anything we store. keep_alive keeps the model resident so embeds stay fast (~ms).
    prefix = DOC_PREFIX if kind == "document" else QUERY_PREFIX
    r = _http.post(f"{OLLAMA_URL}/api/embeddings",
                   json={"model": EMBED_MODEL, "prompt": prefix + text, "keep_alive": "30m"})
    r.raise_for_status()
    return r.json()["embedding"]


def _entity_id(name: str) -> str:
    return str(uuid.uuid5(NS, "entity:" + name.strip().lower()))


def _relation_id(source: str, relation: str, target: str) -> str:
    key = f"rel:{source.strip().lower()}|{relation.strip().lower()}|{target.strip().lower()}"
    return str(uuid.uuid5(NS, key))


# --- observation normalization (observations are stored as {text, ts, source}) --- #
def _coerce_obs(observations: list) -> list[dict]:
    """Normalize observations to dicts, tolerating legacy plain-string entries."""
    out = []
    for o in observations or []:
        if isinstance(o, dict):
            out.append({"text": o.get("text", "").strip(),
                        "ts": o.get("ts"), "source": o.get("source") or ""})
        elif isinstance(o, str) and o.strip():
            out.append({"text": o.strip(), "ts": None, "source": ""})
    return [o for o in out if o["text"]]


def _obs_texts(observations: list) -> list[str]:
    return [o["text"] for o in _coerce_obs(observations)]


def _make_obs(texts: list[str], source: str) -> list[dict]:
    ts = _now()
    return [{"text": t.strip(), "ts": ts, "source": source} for t in texts if t.strip()]


def _retrieve_entity(name: str) -> dict | None:
    res = _q("POST", f"/collections/{ENTITIES}/points",
             json={"ids": [_entity_id(name)], "with_payload": True})["result"]
    return res[0]["payload"] if res else None


def _scroll(collection: str, flt: dict | None, with_vector: bool = False) -> list[dict]:
    body = {"limit": 1000, "with_payload": True, "with_vector": with_vector}
    if flt is not None:
        body["filter"] = flt
    res = _q("POST", f"/collections/{collection}/points/scroll", json=body)["result"]
    if with_vector:
        return res["points"]  # full points (id, payload, vector)
    return [p["payload"] for p in res["points"]]


def _retrieve_entities(names: list[str]) -> dict[str, dict]:
    """Batch-fetch entity payloads by name. Returns {name: payload} for those that exist."""
    if not names:
        return {}
    ids = [_entity_id(n) for n in names]
    res = _q("POST", f"/collections/{ENTITIES}/points",
             json={"ids": ids, "with_payload": True})["result"]
    return {p["payload"]["name"]: p["payload"] for p in res}


def _match(key: str, value: str) -> dict:
    return {"key": key, "match": {"value": value}}


def _embed_text(name: str, etype: str, obs: list[dict]) -> str:
    return f"{name} ({etype})\n" + "\n".join(_obs_texts(obs))


def _store_entity(name: str, etype: str, obs: list[dict]) -> None:
    vec = _embed(_embed_text(name, etype, obs), "document")
    _q("PUT", f"/collections/{ENTITIES}/points?wait=true",
       json={"points": [{"id": _entity_id(name), "vector": vec,
                         "payload": {"name": name, "type": etype,
                                     "observations": obs, "updated": _now()}}]})


def _chunk(text: str, size: int, overlap: int) -> list[str]:
    text = text.strip()
    if len(text) <= size:
        return [text] if text else []
    chunks, start = [], 0
    while start < len(text):
        chunks.append(text[start:start + size])
        start += max(1, size - overlap)
    return chunks


# --- hybrid (dense + lexical) entity retrieval ------------------------------ #
_STOP = {"the", "a", "an", "of", "to", "and", "or", "is", "are", "in", "on", "for",
         "what", "which", "how", "do", "does", "this", "that", "with", "it", "its"}


def _tokens(text: str) -> list[str]:
    cur, out = [], []
    for ch in text.lower():
        if ch.isalnum():
            cur.append(ch)
        elif cur:
            out.append("".join(cur)); cur = []
    if cur:
        out.append("".join(cur))
    return [t for t in out if len(t) >= 2 and t not in _STOP]


def _entity_blob(payload: dict) -> str:
    return payload.get("name", "") + " " + " ".join(_obs_texts(payload.get("observations", [])))


def _hybrid(query: str, limit: int) -> list[dict]:
    """Rank entities by Reciprocal Rank Fusion of dense (semantic) and lexical (keyword)
    rankings. Catches both "what is this about" (dense) and exact tokens like error codes
    or flag names that embeddings tend to miss (lexical)."""
    # dense ranking
    dense = _q("POST", f"/collections/{ENTITIES}/points/query",
               json={"query": _embed(query, "query"), "limit": max(limit * 4, 20),
                     "with_payload": True})["result"]["points"]
    payloads: dict[str, dict] = {}
    dense_rank, dense_score = {}, {}
    for i, h in enumerate(dense):
        name = h["payload"]["name"]
        payloads[name] = h["payload"]; dense_rank[name] = i; dense_score[name] = h["score"]
    # lexical ranking over the whole (small) entity corpus
    qtok = _tokens(query)
    lex: dict[str, int] = {}
    if qtok:
        for p in _scroll(ENTITIES, None):
            toks = _tokens(_entity_blob(p))
            s = sum(toks.count(t) for t in qtok)
            if s:
                lex[p["name"]] = s; payloads.setdefault(p["name"], p)
    lex_rank = {n: i for i, n in enumerate(sorted(lex, key=lambda n: lex[n], reverse=True))}
    # fuse (RRF, k=60)
    fused = []
    for name in payloads:
        score = 0.0
        if name in dense_rank:
            score += 1.0 / (60 + dense_rank[name])
        if name in lex_rank:
            score += 1.0 / (60 + lex_rank[name])
        fused.append((name, score))
    fused.sort(key=lambda x: x[1], reverse=True)
    out = []
    for name, _ in fused[:limit]:
        p = payloads[name]
        out.append({"name": p.get("name"), "type": p.get("type"),
                    "observations": p.get("observations", []),
                    "score": round(dense_score.get(name, 0.0), 4),
                    "matched": ("dense" if name in dense_rank else "") +
                               ("+keyword" if name in lex_rank else "")})
    return out


# --------------------------------------------------------------------------- #
# entity tools
# --------------------------------------------------------------------------- #
@mcp.tool()
def kg_upsert_entity(name: str, entity_type: str, observations: list[str], source: str = "") -> str:
    """Create or replace an entity (a named node) in the knowledge graph.

    Use this to record a person, project, concept, file, decision, etc.
    `observations` is a list of short standalone facts about the entity.
    `source` is optional provenance (e.g. the project/topic this was learned in);
    every observation is automatically timestamped.
    If the entity already exists, its type and observations are REPLACED.
    To add facts without losing existing ones, use kg_add_observations instead.
    """
    _ensure_collections()
    obs = _make_obs(observations, source)
    _store_entity(name, entity_type, obs)
    return f"Upserted entity '{name}' ({entity_type}) with {len(obs)} observation(s)."


@mcp.tool()
def kg_add_observations(name: str, observations: list[str], source: str = "") -> str:
    """Append new observations (facts) to an existing entity and re-embed it.

    Each new observation is timestamped and tagged with `source` provenance.
    Creates the entity with type 'unknown' if it does not yet exist.
    """
    _ensure_collections()
    payload = _retrieve_entity(name)
    etype = payload.get("type", "unknown") if payload else "unknown"
    existing = _coerce_obs(payload.get("observations", [])) if payload else []
    have = {o["text"] for o in existing}
    new = _make_obs([t for t in observations if t.strip() and t.strip() not in have], source)
    merged = existing + new
    _store_entity(name, etype, merged)
    return f"Added {len(new)} new observation(s) to '{name}' (now {len(merged)} total)."


@mcp.tool()
def kg_relate(source: str, relation: str, target: str) -> str:
    """Add a directed, labeled edge: (source) -[relation]-> (target).

    Example: kg_relate("Brona", "owns", "claude-kg project").
    Any entity that doesn't exist yet is auto-created as a stub so the edge is valid.
    """
    _ensure_collections()
    for n in (source, target):
        if _retrieve_entity(n) is None:
            _store_entity(n, "unknown", [])
    _q("PUT", f"/collections/{RELATIONS}/points?wait=true",
       json={"points": [{"id": _relation_id(source, relation, target), "vector": [0.0],
                         "payload": {"source": source, "relation": relation,
                                     "target": target, "ts": _now()}}]})
    return f"Related: ({source}) -[{relation}]-> ({target})."


@mcp.tool()
def kg_search(query: str, limit: int = 5) -> list[dict[str, Any]]:
    """Hybrid search over entities (semantic + keyword). Returns the best matches.

    For most recall use kg_recall instead — it also pulls in graph context.
    """
    _ensure_collections()
    return _hybrid(query, limit)


@mcp.tool()
def kg_recall(query: str, limit: int = 5, depth: int = 1) -> dict[str, Any]:
    """Hybrid recall: rank the most relevant entities by semantic + keyword search, then
    expand the graph `depth` hops around them so you get the matching facts AND context.

    This is the most useful single call for "what do we know about X" — it returns the
    seed matches (ranked by similarity), the related entities pulled in via relations
    (with their observations), and every edge connecting the result set. Prefer this
    over plain kg_search when relationships matter.
    """
    _ensure_collections()
    seeds = _hybrid(query, limit)

    # Expand outward from the seed names, collecting edges and reachable entity names.
    visited = {s["name"] for s in seeds}
    frontier = set(visited)
    edges: list[dict[str, str]] = []
    for _ in range(max(0, depth)):
        if not frontier:
            break
        nxt: set[str] = set()
        for node in frontier:
            for p in _scroll(RELATIONS, {"should": [_match("source", node), _match("target", node)]}):
                edge = {"source": p["source"], "relation": p["relation"], "target": p["target"]}
                if edge not in edges:
                    edges.append(edge)
                for other in (p["source"], p["target"]):
                    if other not in visited:
                        visited.add(other)
                        nxt.add(other)
        frontier = nxt

    # Hydrate the related (non-seed) entities with their observations.
    seed_names = {s["name"] for s in seeds}
    related_payloads = _retrieve_entities([n for n in visited if n not in seed_names])
    related = [{"name": p["name"], "type": p.get("type"), "observations": p.get("observations", [])}
               for p in related_payloads.values()]
    return {"query": query, "seeds": seeds, "related": related, "edges": edges}


@mcp.tool()
def kg_get(name: str) -> dict[str, Any]:
    """Fetch one entity by exact name, including its outgoing and incoming relations."""
    _ensure_collections()
    payload = _retrieve_entity(name)
    if payload is None:
        return {"error": f"No entity named '{name}'."}
    out = _scroll(RELATIONS, {"must": [_match("source", name)]})
    inc = _scroll(RELATIONS, {"must": [_match("target", name)]})
    return {
        "name": payload.get("name"),
        "type": payload.get("type"),
        "updated": payload.get("updated"),
        "observations": payload.get("observations", []),
        "outgoing": [{"relation": p["relation"], "target": p["target"]} for p in out],
        "incoming": [{"relation": p["relation"], "source": p["source"]} for p in inc],
    }


@mcp.tool()
def kg_neighbors(name: str, depth: int = 1) -> dict[str, Any]:
    """Traverse the graph outward from an entity up to `depth` hops.

    Returns the set of reachable entities and the edges connecting them.
    Useful for "what is related to X and how".
    """
    _ensure_collections()
    if _retrieve_entity(name) is None:
        return {"error": f"No entity named '{name}'."}
    visited: set[str] = {name}
    frontier = {name}
    edges: list[dict[str, str]] = []
    for _ in range(max(1, depth)):
        nxt: set[str] = set()
        for node in frontier:
            recs = _scroll(RELATIONS, {"should": [_match("source", node), _match("target", node)]})
            for p in recs:
                edge = {"source": p["source"], "relation": p["relation"], "target": p["target"]}
                if edge not in edges:
                    edges.append(edge)
                for other in (p["source"], p["target"]):
                    if other not in visited:
                        visited.add(other)
                        nxt.add(other)
        frontier = nxt
        if not frontier:
            break
    return {"root": name, "entities": sorted(visited), "edges": edges}


@mcp.tool()
def kg_merge(source_name: str, target_name: str) -> str:
    """Merge one entity into another: combine observations, repoint every relation from
    `source_name` onto `target_name`, then delete `source_name`.

    Use this to fix duplicates (e.g. "claude-kg" and "Claude KG"). The surviving node
    is `target_name`; its type wins unless it is 'unknown', in which case source's type
    is adopted.
    """
    _ensure_collections()
    src = _retrieve_entity(source_name)
    if src is None:
        return f"No entity named '{source_name}' to merge."
    if source_name == target_name:
        return "Source and target are the same entity; nothing to merge."
    tgt = _retrieve_entity(target_name)

    src_obs = _coerce_obs(src.get("observations", []))
    tgt_obs = _coerce_obs(tgt.get("observations", [])) if tgt else []
    have = {o["text"] for o in tgt_obs}
    merged_obs = tgt_obs + [o for o in src_obs if o["text"] not in have]
    etype = (tgt.get("type") if tgt and tgt.get("type") not in (None, "unknown")
             else src.get("type")) or "unknown"
    _store_entity(target_name, etype, merged_obs)

    # Repoint edges touching the source onto the target (skip self-loops).
    moved = 0
    for p in _scroll(RELATIONS, {"must": [_match("source", source_name)]}):
        if p["target"] != target_name:
            kg_relate(target_name, p["relation"], p["target"]); moved += 1
    for p in _scroll(RELATIONS, {"must": [_match("target", source_name)]}):
        if p["source"] != target_name:
            kg_relate(p["source"], p["relation"], target_name); moved += 1

    # delete source (also removes its now-stale edges)
    _q("POST", f"/collections/{ENTITIES}/points/delete?wait=true", json={"points": [_entity_id(source_name)]})
    _q("POST", f"/collections/{RELATIONS}/points/delete?wait=true",
       json={"filter": {"should": [_match("source", source_name), _match("target", source_name)]}})
    return (f"Merged '{source_name}' into '{target_name}': "
            f"{len(merged_obs)} observation(s), {moved} relation(s) repointed.")


@mcp.tool()
def kg_find_duplicates(threshold: float = 0.92, limit: int = 20) -> list[dict[str, Any]]:
    """Find probable duplicate entities — pairs whose embeddings are more similar than
    `threshold` (cosine, 0–1). Review the pairs, then clean up with kg_merge.

    Returns up to `limit` of the highest-similarity pairs.
    """
    _ensure_collections()
    points = _scroll(ENTITIES, None, with_vector=True)
    pairs, seen = [], set()
    for p in points:
        name = p["payload"]["name"]
        res = _q("POST", f"/collections/{ENTITIES}/points/query",
                 json={"query": p["vector"], "limit": 5, "with_payload": True,
                       "score_threshold": threshold})["result"]
        for h in res["points"]:
            other = h["payload"]["name"]
            if other == name:
                continue
            key = tuple(sorted((name, other)))
            if key in seen:
                continue
            seen.add(key)
            pairs.append({"a": key[0], "b": key[1], "score": round(h["score"], 4)})
    pairs.sort(key=lambda x: x["score"], reverse=True)
    return pairs[:limit]


@mcp.tool()
def kg_delete_entity(name: str) -> str:
    """Delete an entity and every relation that touches it."""
    _ensure_collections()
    _q("POST", f"/collections/{ENTITIES}/points/delete?wait=true",
       json={"points": [_entity_id(name)]})
    _q("POST", f"/collections/{RELATIONS}/points/delete?wait=true",
       json={"filter": {"should": [_match("source", name), _match("target", name)]}})
    return f"Deleted entity '{name}' and its relations."


@mcp.tool()
def kg_forget_observations(name: str, substrings: list[str]) -> str:
    """Retract observations from an entity by case-insensitive substring match, then re-embed.

    Use this when a fact is wrong or superseded (the user changed their mind). Every
    observation whose text contains ANY of `substrings` (case-insensitive) is dropped;
    the rest are kept and the entity is re-embedded so recall reflects the change.
    The entity itself survives even if all its observations are removed — use
    kg_delete_entity to remove the entity entirely.
    """
    _ensure_collections()
    payload = _retrieve_entity(name)
    if payload is None:
        return f"No entity named '{name}'."
    etype = payload.get("type", "unknown")
    existing = _coerce_obs(payload.get("observations", []))
    needles = [s.lower() for s in substrings if s.strip()]
    if not needles:
        return "No substrings given; nothing forgotten."
    kept = [o for o in existing if not any(n in o["text"].lower() for n in needles)]
    removed = [o["text"] for o in existing if o not in kept]
    if not removed:
        return f"No observation on '{name}' matched {needles}; nothing forgotten."
    _store_entity(name, etype, kept)
    listed = "; ".join(removed)
    return f"Forgot {len(removed)} observation(s) from '{name}' (now {len(kept)} total): {listed}"


# --------------------------------------------------------------------------- #
# document RAG tools (separate collection from the curated graph)
# --------------------------------------------------------------------------- #
@mcp.tool()
def kg_ingest_document(name: str, text: str, source: str = "",
                       chunk_chars: int = 1200, overlap: int = 200) -> str:
    """Chunk, embed, and store a free-text document for retrieval (RAG).

    Documents live in their own collection, separate from the curated entity graph —
    use this for reference material (docs, transcripts, notes) you want to search over.
    Re-ingesting the same `name` replaces its previous chunks.
    """
    _ensure_collections()
    # clear any prior chunks for this doc name
    _q("POST", f"/collections/{DOCUMENTS}/points/delete?wait=true",
       json={"filter": {"must": [_match("doc", name)]}})
    chunks = _chunk(text, max(200, chunk_chars), max(0, min(overlap, chunk_chars - 1)))
    ts = _now()
    points = []
    for i, ch in enumerate(chunks):
        points.append({"id": str(uuid.uuid5(NS, f"doc:{name.lower()}:{i}")),
                       "vector": _embed(ch, "document"),
                       "payload": {"doc": name, "chunk": i, "text": ch,
                                   "source": source, "ts": ts}})
    if points:
        _q("PUT", f"/collections/{DOCUMENTS}/points?wait=true", json={"points": points})
    return f"Ingested document '{name}' as {len(points)} chunk(s)."


@mcp.tool()
def kg_search_documents(query: str, limit: int = 5) -> list[dict[str, Any]]:
    """Semantic search over ingested documents. Returns the most relevant chunks."""
    _ensure_collections()
    res = _q("POST", f"/collections/{DOCUMENTS}/points/query",
             json={"query": _embed(query), "limit": limit, "with_payload": True})["result"]
    return [{"doc": h["payload"].get("doc"), "chunk": h["payload"].get("chunk"),
             "text": h["payload"].get("text"), "source": h["payload"].get("source"),
             "score": round(h["score"], 4)} for h in res["points"]]


@mcp.tool()
def kg_stats() -> dict[str, Any]:
    """Return counts of entities, relations, and document chunks currently stored."""
    _ensure_collections()
    def count(c):
        return _q("POST", f"/collections/{c}/points/count", json={"exact": True})["result"]["count"]
    return {"entities": count(ENTITIES), "relations": count(RELATIONS),
            "document_chunks": count(DOCUMENTS),
            "qdrant_url": QDRANT_URL, "embed_model": EMBED_MODEL, "embed_dim": EMBED_DIM}


if __name__ == "__main__":
    mcp.run()
