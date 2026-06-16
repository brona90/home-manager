#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp[cli]>=1.2.0", "httpx>=0.27.0"]
# ///
"""Local, free memory capture for claude-kg.

Reads a Claude session transcript, asks a LOCAL Ollama model to extract durable facts as
structured JSON, then writes them to the knowledge graph deterministically. No Claude API
call and no autonomous agent loop — just local extraction + plain function calls, so it's
cheap, offline, and safe to run from a SessionEnd hook.

Usage:  uv run capture_local.py <transcript_path> [source]
Env:    CLAUDE_KG_CAPTURE_OLLAMA_MODEL (default qwen2.5:7b)
"""
import json
import os
import sys

import httpx

import kg_server as kg

MODEL = os.environ.get("CLAUDE_KG_CAPTURE_OLLAMA_MODEL", "qwen2.5:7b")
MAX_CHARS = 16000  # keep the most recent slice of the conversation within local-model context

SCHEMA = {
    "type": "object",
    "properties": {
        "entities": {"type": "array", "items": {"type": "object", "properties": {
            "name": {"type": "string"}, "type": {"type": "string"},
            "observations": {"type": "array", "items": {"type": "string"}},
        }, "required": ["name", "type", "observations"]}},
        "relations": {"type": "array", "items": {"type": "object", "properties": {
            "source": {"type": "string"}, "relation": {"type": "string"}, "target": {"type": "string"},
        }, "required": ["source", "relation", "target"]}},
    },
    "required": ["entities", "relations"],
}

SYSTEM = (
    "You extract durable, reusable knowledge from a software engineering chat transcript "
    "for a long-term knowledge graph. Capture ONLY lasting facts: a project's purpose or "
    "architecture, a decision and its rationale, how systems/services connect, stable "
    "configuration, and the user's lasting preferences. IGNORE secrets, transient state, "
    "one-off command output, and trivia. Entity names are canonical proper nouns (tools, "
    "projects, people, services). Observations are short standalone facts. Relations are "
    "directed: source -[relation]-> target (e.g. Helios uses InfluxDB). If nothing durable "
    "exists, return empty arrays."
)


def _conversation(transcript_path: str) -> str:
    lines = []
    with open(transcript_path, encoding="utf-8", errors="ignore") as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                obj = json.loads(ln)
            except json.JSONDecodeError:
                continue
            msg = obj.get("message") or {}
            role = msg.get("role") or obj.get("type") or ""
            content = msg.get("content")
            text = ""
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = " ".join(b.get("text", "") for b in content
                                 if isinstance(b, dict) and b.get("type") == "text")
            text = text.strip()
            if role in ("user", "assistant") and text:
                lines.append(f"{role.upper()}: {text}")
    blob = "\n".join(lines)
    return blob[-MAX_CHARS:]


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: capture_local.py <transcript_path> [source]", file=sys.stderr)
        return 2
    transcript, source = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
    convo = _conversation(transcript)
    if len(convo) < 200:
        print("transcript too thin; nothing to capture")
        return 0

    r = httpx.post(f"{kg.OLLAMA_URL}/api/chat", timeout=300.0, json={
        "model": MODEL, "stream": False, "format": SCHEMA, "keep_alive": "10m",
        "options": {"temperature": 0.1, "num_ctx": 8192},
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": "Transcript:\n\n" + convo}],
    })
    r.raise_for_status()
    data = json.loads(r.json()["message"]["content"])

    n_e = n_o = n_r = 0
    for e in data.get("entities", []):
        name = (e.get("name") or "").strip()
        if not name:
            continue
        obs = [o for o in e.get("observations", []) if isinstance(o, str) and o.strip()]
        if kg._retrieve_entity(name) is None:
            kg.kg_upsert_entity(name, (e.get("type") or "unknown").strip() or "unknown", obs, source=source)
        else:
            kg.kg_add_observations(name, obs, source=source)
        n_e += 1; n_o += len(obs)
    for rel in data.get("relations", []):
        s, p, t = (rel.get("source") or "").strip(), (rel.get("relation") or "").strip(), (rel.get("target") or "").strip()
        if s and p and t:
            kg.kg_relate(s, p, t); n_r += 1

    print(f"captured: {n_e} entities, {n_o} observations, {n_r} relations (model={MODEL})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
