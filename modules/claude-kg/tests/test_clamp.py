"""The model-driven MCP tools bound their numeric inputs.

A tool call is the model's choice, so a depth of 10000 or a limit of 10**6 is
one call away. Each test passes values far outside the documented range on
both sides and checks what actually reached Qdrant (or the helper below it).
"""
import unittest
from unittest import mock

import kg_server as kg
from fake_qdrant import install

CHAIN = 10  # n0 - n1 - ... - n10: depth hops from n0 reach exactly `depth` edges


class Clamping(unittest.TestCase):
    def setUp(self):
        self.fake = install(self, kg)
        self.fake.put(kg.ENTITIES, [
            {"id": kg._entity_id(f"n{i}"), "vector": [0.0],
             "payload": {"name": f"n{i}", "type": "t", "observations": []}}
            for i in range(CHAIN + 1)])
        self.fake.put(kg.RELATIONS, [
            {"id": f"r{i}", "vector": [0.0],
             "payload": {"source": f"n{i}", "relation": "next", "target": f"n{i + 1}"}}
            for i in range(CHAIN)])
        self.fake.put(kg.DOCUMENTS, [])

    def test_clamp_helper(self):
        self.assertEqual(kg._clamp(-5, 1, 50), 1)
        self.assertEqual(kg._clamp(10**6, 1, 50), 50)
        self.assertEqual(kg._clamp(7, 1, 50), 7)

    def test_search_limit(self):
        with mock.patch.object(kg, "_hybrid", return_value=[]) as h:
            kg.kg_search("q", limit=10**6)
            kg.kg_search("q", limit=-3)
        self.assertEqual([c.args[1] for c in h.call_args_list], [50, 1])

    def test_recall_limit_and_depth(self):
        seed = [{"name": "n0", "type": "t", "observations": [], "score": 1.0, "matched": "dense"}]
        with mock.patch.object(kg, "_hybrid", return_value=seed) as h:
            deep = kg.kg_recall("q", limit=10**6, depth=10**4)
            none = kg.kg_recall("q", limit=0, depth=-1)
        self.assertEqual([c.args[1] for c in h.call_args_list], [50, 1])
        self.assertEqual(len(deep["edges"]), 3)
        self.assertEqual(len(none["edges"]), 0)

    def test_neighbors_depth(self):
        self.assertEqual(len(kg.kg_neighbors("n0", depth=10**4)["edges"]), 3)
        self.assertEqual(len(kg.kg_neighbors("n0", depth=0)["edges"]), 1)
        self.assertEqual(len(kg.kg_neighbors("n0", depth=2)["edges"]), 2)

    def test_find_duplicates_threshold(self):
        def thresholds():
            return [b["score_threshold"] for m, p, b in self.fake.calls if p.endswith("/points/query")]

        kg.kg_find_duplicates(threshold=7.0, limit=10**6)
        self.assertEqual(set(thresholds()), {1.0})
        self.fake.calls.clear()
        kg.kg_find_duplicates(threshold=-1.0)
        self.assertEqual(set(thresholds()), {0.0})

    def test_search_documents_limit(self):
        kg.kg_search_documents("q", limit=10**6)
        kg.kg_search_documents("q", limit=0)
        limits = [b["limit"] for m, p, b in self.fake.calls if p.endswith("/documents/points/query")]
        self.assertEqual(limits, [50, 1])

    def _chunks(self):
        return sorted((p["payload"] for p in self.fake.cols[kg.DOCUMENTS].values()),
                      key=lambda p: p["chunk"])

    def test_ingest_chunk_floor_and_overlap(self):
        # chunk_chars=1 would mean a chunk per character; overlap past chunk_chars
        # would stall the chunker's advance. Both are bounded.
        kg.kg_ingest_document("d", "x" * 1000, chunk_chars=1, overlap=10**6)
        chunks = self._chunks()
        self.assertEqual(len(chunks[0]["text"]), 200)
        self.assertTrue(all(len(c["text"]) <= 200 for c in chunks))

    def test_ingest_chunk_ceiling(self):
        kg.kg_ingest_document("d", "y" * 25000, chunk_chars=10**9, overlap=0)
        chunks = self._chunks()
        self.assertEqual([len(c["text"]) for c in chunks], [10000, 10000, 5000])

    def test_ingest_negative_overlap(self):
        kg.kg_ingest_document("d", "z" * 1000, chunk_chars=500, overlap=-50)
        self.assertEqual([len(c["text"]) for c in self._chunks()], [500, 500])


if __name__ == "__main__":
    unittest.main()
