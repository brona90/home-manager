"""_scroll must return EVERY matching point, not the first page.

Reading only the first page truncated recall, duplicate detection and export
past 1000 points, and reembed then deleted what export had missed. The sizes
here are chosen so that a single-call _scroll fails visibly: 2500 points is
three pages, and 1000 is exactly one full page with nothing after it.
"""
import unittest

import kg_server as kg
from fake_qdrant import entity_points, install


class ScrollPagination(unittest.TestCase):
    def setUp(self):
        self.fake = install(self, kg)

    def test_follows_next_page_offset_across_pages(self):
        self.fake.put(kg.ENTITIES, entity_points(kg, 2500))
        got = kg._scroll(kg.ENTITIES, None)
        self.assertEqual(len(got), 2500)
        self.assertEqual({p["name"] for p in got}, {f"e{i}" for i in range(2500)})
        calls = self.fake.scroll_calls(kg.ENTITIES)
        self.assertEqual(len(calls), 3)
        self.assertNotIn("offset", calls[0])
        self.assertIn("offset", calls[1])

    def test_exactly_one_full_page_stops_after_one_call(self):
        self.fake.put(kg.ENTITIES, entity_points(kg, kg.SCROLL_PAGE))
        self.assertEqual(len(kg._scroll(kg.ENTITIES, None)), kg.SCROLL_PAGE)
        self.assertEqual(len(self.fake.scroll_calls(kg.ENTITIES)), 1)

    def test_empty_collection(self):
        self.fake.put(kg.ENTITIES, [])
        self.assertEqual(kg._scroll(kg.ENTITIES, None), [])

    def test_with_vector_returns_full_points_across_pages(self):
        self.fake.put(kg.ENTITIES, entity_points(kg, 1500))
        got = kg._scroll(kg.ENTITIES, None, with_vector=True)
        self.assertEqual(len(got), 1500)
        self.assertTrue(all({"id", "payload", "vector"} <= set(p) for p in got))

    def test_filter_is_sent_on_every_page(self):
        pts = [{"id": f"r{i}", "vector": [0.0],
                "payload": {"source": "hub", "relation": "r", "target": f"n{i}"}}
               for i in range(2100)]
        pts.append({"id": "other", "vector": [0.0],
                    "payload": {"source": "x", "relation": "r", "target": "y"}})
        self.fake.put(kg.RELATIONS, pts)
        flt = {"must": [kg._match("source", "hub")]}
        got = kg._scroll(kg.RELATIONS, flt)
        self.assertEqual(len(got), 2100)
        calls = self.fake.scroll_calls(kg.RELATIONS)
        self.assertEqual(len(calls), 3)
        self.assertTrue(all(c["filter"] == flt for c in calls))

    def test_find_duplicates_sees_points_past_the_first_page(self):
        # A consumer, not just the helper: kg_find_duplicates queries once per point.
        self.fake.put(kg.ENTITIES, entity_points(kg, 1200))
        kg.kg_find_duplicates()
        queries = [p for m, p, _ in self.fake.calls if p.endswith("/points/query")]
        self.assertEqual(len(queries), 1200)


if __name__ == "__main__":
    unittest.main()
