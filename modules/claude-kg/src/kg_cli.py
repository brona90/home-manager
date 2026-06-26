#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp[cli]>=1.2.0", "httpx>=0.27.0"]
# ///
"""Terminal CLI for browsing/editing the claude-kg graph outside of Claude.

Usage (via the `kg` wrapper on PATH, or `uv run kg_cli.py`):
  kg stats
  kg recall "<query>" [limit] [depth]
  kg search "<query>" [limit]
  kg docs "<query>" [limit]
  kg get "<name>"
  kg list [type]
  kg add "<name>" "<fact>" ["<fact2>" ...]
  kg relate "<source>" "<relation>" "<target>"
  kg dupes [threshold]
  kg merge "<source>" "<target>"
  kg delete "<name>"
  kg forget "<name>" "<substring>" ["<substring2>" ...]
"""
import json
import sys

import kg_server as kg


def _pp(obj):
    print(json.dumps(obj, indent=2, ensure_ascii=False))


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 1
    cmd, rest = argv[0], argv[1:]
    if cmd == "stats":
        _pp(kg.kg_stats())
    elif cmd == "recall":
        _pp(kg.kg_recall(rest[0], int(rest[1]) if len(rest) > 1 else 5,
                         int(rest[2]) if len(rest) > 2 else 1))
    elif cmd == "search":
        _pp(kg.kg_search(rest[0], int(rest[1]) if len(rest) > 1 else 5))
    elif cmd == "docs":
        _pp(kg.kg_search_documents(rest[0], int(rest[1]) if len(rest) > 1 else 5))
    elif cmd == "get":
        _pp(kg.kg_get(rest[0]))
    elif cmd == "list":
        flt = {"must": [kg._match("type", rest[0])]} if rest else None
        names = sorted(p["name"] for p in kg._scroll(kg.ENTITIES, flt))
        for n in names:
            print(n)
        print(f"\n{len(names)} entit{'y' if len(names)==1 else 'ies'}")
    elif cmd == "add":
        print(kg.kg_add_observations(rest[0], rest[1:], source="cli"))
    elif cmd == "relate":
        print(kg.kg_relate(rest[0], rest[1], rest[2]))
    elif cmd == "dupes":
        _pp(kg.kg_find_duplicates(float(rest[0]) if rest else 0.92))
    elif cmd == "merge":
        print(kg.kg_merge(rest[0], rest[1]))
    elif cmd == "delete":
        print(kg.kg_delete_entity(rest[0]))
    elif cmd == "forget":
        print(kg.kg_forget_observations(rest[0], rest[1:]))
    else:
        print(f"unknown command: {cmd}\n{__doc__}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
