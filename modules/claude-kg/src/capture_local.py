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

Secret filter. Sessions routinely contain secrets: a token pasted to debug an API
call, a `sops -d` printed to the terminal, a key file someone cat'ed. The graph is
recalled into EVERY later session and is exported by kg-reembed and snapshotted daily,
so a secret that lands there gets copied all over the machine. SYSTEM below asks the
model to ignore secrets. That is a request, not a control: a 7B model will
sometimes quote one back. Two deterministic passes back it up:
  1. the transcript is redacted BEFORE it is sliced or sent to Ollama. Redacting
     after the slice could leave a cut-off key with its prefix gone, and nothing
     would match it;
  2. any extracted entity, observation or relation that still matches is DROPPED
     before anything is written.
Each hit is logged to stdout, which kg-capture-hook appends to capture.log. The log
gives the pattern NAME and a count, plus the entity name for a dropped observation,
since that name has itself been checked. It never gives the matched text.

This covers the local backend only. The `claude' backend in capture_memory.sh hands
the raw transcript to a headless Claude, and this file never sees it.
"""
import json
import math
import os
import re
import sys
from collections import Counter

import httpx

import kg_server as kg

MODEL = os.environ.get("CLAUDE_KG_CAPTURE_OLLAMA_MODEL", "qwen2.5:7b")
MAX_CHARS = 16000  # keep the most recent slice of the conversation within local-model context

# --------------------------------------------------------------------------- #
# secret filter
# --------------------------------------------------------------------------- #
# Named patterns, checked in this order. The PEM pattern comes first so that the
# body of a key block is consumed whole and never reaches the entropy pass line by
# line. A block with no END line, e.g. a truncated paste, is redacted to the end of
# the text. Leaving its body in would be the worse failure.
SECRET_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("pem-private-key", re.compile(
        r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY[A-Z ]*-----.*?"
        r"(?:-----END [A-Z0-9 ]*PRIVATE KEY[A-Z ]*-----|\Z)", re.S)),
    # age's identity is bech32 and conventionally upper case, but bech32 is case-
    # insensitive, so a lower-cased key is the same secret.
    ("age-secret-key", re.compile(r"AGE-SECRET-KEY-1[0-9A-Z]+", re.I)),
    # Every GitHub token prefix: classic PAT, OAuth, user-to-server, server-to-
    # server, refresh, and fine-grained PAT.
    ("github-token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
    # Long-lived (AKIA) and STS temporary (ASIA) access key ids. The paired secret
    # key has no prefix, and it is the entropy pass below that catches it.
    ("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    # Not in the original list. This is the key a Claude session is most likely
    # to contain.
    ("anthropic-key", re.compile(r"\bsk-ant-[A-Za-z0-9_\-]{20,}")),
]

# High-entropy pass, for secrets with no recognisable prefix (an AWS secret key,
# a generic API key, a JWT segment). A run of 32+ token characters is redacted
# when all three of these hold:
#   - it mixes upper case, lower case AND digits. This lets through the long
#     strings this machine's sessions are full of that are not secrets: git SHAs
#     and UUIDs (lower-case hex), nix store hashes (lower-case base32), GPG
#     fingerprints (upper-case hex), and most paths;
#   - it averages at least ENTROPY_BITS bits per character;
#   - less than WORDY_MAX of it is word-like runs ([A-Z]?[a-z]{3,}). Without this
#     rule, long CamelCase identifiers with a digit in them (entropy 3.9-4.4)
#     fall on the secret side.
# MEASURED, 50k random tokens per row (2026-11-23): caught 98.5% at 32 chars,
# 99.5% at 36, 99.7% at 40 and 99.99% at 64. Entropy and wordiness cannot
# separate every short random token from every identifier. The ones missed are
# mostly 32-char tokens that happen to read as words, and they are the price of
# not redacting every CamelCase identifier. A known false positive the other way:
# a mixed identifier like `x86_64-linux-HomeManagerGeneration2026-11-23` IS
# redacted. Losing one identifier from a fact costs little; storing a key costs a
# rotation. tests/test_capture_filter.py pins both sides.
_TOKEN = re.compile(r"[A-Za-z0-9+/_\-]{32,}={0,2}")
_WORD = re.compile(r"[A-Z]?[a-z]{3,}")
ENTROPY_BITS = 4.2
WORDY_MAX = 0.6


def _entropy(s: str) -> float:
    n = len(s)
    return -sum(c / n * math.log2(c / n) for c in Counter(s).values())


def _wordiness(s: str) -> float:
    return sum(len(m.group(0)) for m in _WORD.finditer(s)) / len(s)


def _looks_random(tok: str) -> bool:
    body = tok.rstrip("=")
    return (any(c.isupper() for c in body) and any(c.islower() for c in body)
            and any(c.isdigit() for c in body) and _entropy(body) >= ENTROPY_BITS
            and _wordiness(body) < WORDY_MAX)


def redact(text: str) -> tuple[str, Counter]:
    """Replace every secret in `text` with `[REDACTED:<kind>]`.

    Returns the redacted text and a Counter of kind -> hits. The Counter never
    holds the matched text, so it is safe to log.
    """
    hits: Counter = Counter()

    def sub(kind):
        def _r(_m):
            hits[kind] += 1
            return f"[REDACTED:{kind}]"
        return _r

    for kind, pat in SECRET_PATTERNS:
        text = pat.sub(sub(kind), text)

    def _entropy_sub(m):
        if _looks_random(m.group(0)):
            hits["high-entropy-token"] += 1
            return "[REDACTED:high-entropy-token]"
        return m.group(0)

    text = _TOKEN.sub(_entropy_sub, text)
    return text, hits


def secret_kinds(text: str) -> Counter:
    """The kinds of secret in `text`; empty when it is clean."""
    return redact(text)[1]


def _fmt(hits: Counter) -> str:
    return ", ".join(f"{k} x{n}" for k, n in sorted(hits.items()))


def filter_extracted(data: dict) -> tuple[list[dict], list[dict], list[str]]:
    """Drop every extracted item that carries a secret.

    Returns (entities, relations, log_lines). An entity whose name or type matches
    is dropped whole, observations and all, and is logged by position because its
    name is the secret. An observation that matches is dropped on its own and is
    logged under its entity's (clean) name. A relation that matches in any field is
    dropped and logged by position. No log line contains matched text.
    """
    log: list[str] = []
    entities: list[dict] = []
    for i, e in enumerate(data.get("entities", []) or []):
        if not isinstance(e, dict):
            continue
        name = (e.get("name") or "").strip()
        etype = (e.get("type") or "").strip()
        hits = secret_kinds(name) + secret_kinds(etype)
        if hits:
            log.append(f"secret-filter: dropped entity #{i} (name/type matched {_fmt(hits)})")
            continue
        kept = []
        for o in e.get("observations", []) or []:
            if not isinstance(o, str) or not o.strip():
                continue
            ohits = secret_kinds(o)
            if ohits:
                log.append(f"secret-filter: dropped observation on entity {name!r} ({_fmt(ohits)})")
            else:
                kept.append(o)
        entities.append({**e, "observations": kept})
    relations: list[dict] = []
    for i, rel in enumerate(data.get("relations", []) or []):
        if not isinstance(rel, dict):
            continue
        hits = sum((secret_kinds(rel.get(k) or "") for k in ("source", "relation", "target")),
                   Counter())
        if hits:
            log.append(f"secret-filter: dropped relation #{i} ({_fmt(hits)})")
            continue
        relations.append(rel)
    return entities, relations, log

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
    # Redact the WHOLE blob, then slice. See "Secret filter" at the top for why the
    # order matters.
    blob, hits = redact("\n".join(lines))
    return blob[-MAX_CHARS:], hits


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: capture_local.py <transcript_path> [source]", file=sys.stderr)
        return 2
    transcript, source = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
    convo, hits = _conversation(transcript)
    if hits:
        print(f"secret-filter: redacted from transcript before extraction: {_fmt(hits)}")
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
    entities, relations, dropped = filter_extracted(data)
    for line in dropped:
        print(line)

    n_e = n_o = n_r = 0
    for e in entities:
        name = (e.get("name") or "").strip()
        if not name:
            continue
        obs = e["observations"]
        if kg._retrieve_entity(name) is None:
            kg.kg_upsert_entity(name, (e.get("type") or "unknown").strip() or "unknown", obs, source=source)
        else:
            kg.kg_add_observations(name, obs, source=source)
        n_e += 1; n_o += len(obs)
    for rel in relations:
        s, p, t = (rel.get("source") or "").strip(), (rel.get("relation") or "").strip(), (rel.get("target") or "").strip()
        if s and p and t:
            kg.kg_relate(s, p, t); n_r += 1

    print(f"captured: {n_e} entities, {n_o} observations, {n_r} relations (model={MODEL})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
