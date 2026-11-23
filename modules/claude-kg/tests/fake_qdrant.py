"""An in-memory stand-in for the slice of Qdrant's REST API that kg_server uses.

Installed by replacing kg_server._q, the single function every Qdrant call goes
through, so the code under test runs unmodified and no socket is ever opened.
The build sandbox has no network anyway, and the live Qdrant must never be the
thing a test talks to.

Scroll paging follows Qdrant's contract: a page holds at most `limit` points,
and `next_page_offset` is the id of the first point of the next page, or null
when there is none. That is the behaviour the pagination fix depends on.
"""
from __future__ import annotations

import copy


def _matches(payload: dict, flt: dict | None) -> bool:
    if not flt:
        return True

    def cond(c):
        return payload.get(c["key"]) == c["match"]["value"]

    if "must" in flt and not all(cond(c) for c in flt["must"]):
        return False
    if "should" in flt and not any(cond(c) for c in flt["should"]):
        return False
    return True


class FakeQdrant:
    def __init__(self):
        self.cols: dict[str, dict] = {}   # collection -> {id: point}, insertion-ordered
        self.calls: list[tuple[str, str, dict]] = []
        self.snapshot_fails: set[str] = set()   # collections whose snapshot returns no name
        self.count_skew: dict[str, int] = {}    # added to the exact count of a collection

    # -- test helpers --------------------------------------------------------
    def put(self, col: str, points: list[dict]) -> None:
        store = self.cols.setdefault(col, {})
        for p in points:
            store[p["id"]] = copy.deepcopy(p)

    def methods(self, method: str) -> list[str]:
        return [path for m, path, _ in self.calls if m == method]

    def scroll_calls(self, col: str) -> list[dict]:
        return [body for m, path, body in self.calls
                if m == "POST" and path == f"/collections/{col}/points/scroll"]

    # -- the _q replacement --------------------------------------------------
    def __call__(self, method: str, path: str, **kwargs) -> dict:
        body = copy.deepcopy(kwargs.get("json") or {})
        self.calls.append((method, path, body))
        parts = path.split("?")[0].strip("/").split("/")
        if parts == ["collections"] and method == "GET":
            return {"result": {"collections": [{"name": n} for n in self.cols]}}
        if parts[0] != "collections" or len(parts) < 2:
            raise AssertionError(f"unexpected Qdrant call {method} {path}")
        col, rest = parts[1], parts[2:]

        if rest == [] and method == "PUT":
            self.cols[col] = {}
            return {"result": True}
        if rest == [] and method == "DELETE":
            del self.cols[col]
            return {"result": True}
        if rest == ["index"]:
            return {"result": {}}
        if rest == ["snapshots"] and method == "POST":
            if col in self.snapshot_fails:
                return {"result": None}
            return {"result": {"name": f"{col}-snapshot.snapshot"}}

        store = self.cols[col]
        if rest == ["points"] and method == "PUT":
            self.put(col, body["points"])
            return {"result": {"status": "completed"}}
        if rest == ["points"] and method == "POST":
            return {"result": [copy.deepcopy(store[i]) for i in body["ids"] if i in store]}
        if rest == ["points", "count"]:
            return {"result": {"count": len(store) + self.count_skew.get(col, 0)}}
        if rest == ["points", "query"]:
            return {"result": {"points": []}}
        if rest == ["points", "delete"]:
            if "points" in body:
                for i in body["points"]:
                    store.pop(i, None)
            else:
                for i in [i for i, p in store.items() if _matches(p["payload"], body["filter"])]:
                    del store[i]
            return {"result": {"status": "completed"}}
        if rest == ["points", "scroll"]:
            pts = [p for p in store.values() if _matches(p["payload"], body.get("filter"))]
            start = 0
            if "offset" in body:
                start = next(i for i, p in enumerate(pts) if p["id"] == body["offset"])
            page = pts[start:start + body["limit"]]
            nxt = pts[start + body["limit"]]["id"] if start + body["limit"] < len(pts) else None
            out = []
            for p in page:
                q = {"id": p["id"], "payload": copy.deepcopy(p["payload"])}
                if body.get("with_vector"):
                    q["vector"] = p.get("vector")
                out.append(q)
            return {"result": {"points": out, "next_page_offset": nxt}}
        raise AssertionError(f"unexpected Qdrant call {method} {path}")


def entity_points(kg, n: int) -> list[dict]:
    return [{"id": kg._entity_id(f"e{i}"), "vector": [0.0],
             "payload": {"name": f"e{i}", "type": "t",
                         "observations": [{"text": f"fact {i}", "ts": None, "source": ""}]}}
            for i in range(n)]


def install(testcase, kg) -> FakeQdrant:
    """Swap kg._q and kg._embed for fakes for the duration of one test."""
    fake = FakeQdrant()
    orig_q, orig_embed, orig_init = kg._q, kg._embed, kg._init_done
    kg._q = fake
    kg._embed = lambda text, kind="query": [0.0]
    kg._init_done = True

    def restore():
        kg._q, kg._embed, kg._init_done = orig_q, orig_embed, orig_init

    testcase.addCleanup(restore)
    return fake
