"""reembed must not DELETE a collection unless every restore point exists.

It deletes the entities and documents collections and rebuilds them. An earlier
version deleted after a truncated export and lost everything past point 1000.
Each failure test checks two things. main() reports failure, and NO DELETE
reached Qdrant, for either collection, even when only the second collection's
checks failed.
"""
import contextlib
import io
import json
import os
import stat
import tempfile
import unittest
from unittest import mock

import kg_server as kg
import reembed
from fake_qdrant import entity_points, install

N_ENTITIES = 2500  # three scroll pages: a single-page export is visibly short


def doc_points(n):
    return [{"id": f"d{i}", "vector": [0.0],
             "payload": {"doc": "readme", "chunk": i, "text": f"chunk {i}", "source": "", "ts": None}}
            for i in range(n)]


class ReembedGuard(unittest.TestCase):
    def setUp(self):
        self.fake = install(self, kg)
        self.fake.put(kg.ENTITIES, entity_points(kg, N_ENTITIES))
        self.fake.put(kg.DOCUMENTS, doc_points(3))
        self.fake.put(kg.RELATIONS, [{"id": "r0", "vector": [0.0],
                                      "payload": {"source": "e0", "relation": "r", "target": "e1"}}])
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.data_dir = tmp.name
        env = mock.patch.dict(os.environ, {"CLAUDE_KG_DATA_DIR": self.data_dir})
        env.start()
        self.addCleanup(env.stop)

    def run_main(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = reembed.main()
        return rc, out.getvalue(), err.getvalue()

    def assert_nothing_deleted(self):
        self.assertEqual(self.fake.methods("DELETE"), [])
        self.assertEqual(len(self.fake.cols[kg.ENTITIES]), N_ENTITIES)
        self.assertEqual(len(self.fake.cols[kg.DOCUMENTS]), 3)

    # -- the happy path, so the failure tests are not passing vacuously -------
    def test_success_snapshots_exports_then_deletes_and_rebuilds(self):
        rc, _, err = self.run_main()
        self.assertEqual(rc, 0, err)
        deletes = [i for i, (m, _, _) in enumerate(self.fake.calls) if m == "DELETE"]
        snaps = [i for i, (m, p, _) in enumerate(self.fake.calls) if p.split("?")[0].endswith("/snapshots")]
        self.assertEqual(len(deletes), 2)
        self.assertEqual(len(snaps), 2)
        self.assertLess(max(snaps), min(deletes))
        self.assertEqual(len(self.fake.cols[kg.ENTITIES]), N_ENTITIES)
        self.assertEqual(len(self.fake.cols[kg.DOCUMENTS]), 3)
        self.assertEqual(len(self.fake.cols[kg.RELATIONS]), 1)  # untouched

        (run_dir,) = os.listdir(os.path.join(self.data_dir, "reembed-exports"))
        path = os.path.join(self.data_dir, "reembed-exports", run_dir, "entities.json")
        with open(path, encoding="utf-8") as f:
            self.assertEqual(len(json.load(f)), N_ENTITIES)
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)

    # -- each restore point failing on its own --------------------------------
    def test_snapshot_without_name_aborts(self):
        self.fake.snapshot_fails.add(kg.ENTITIES)
        rc, _, err = self.run_main()
        self.assertEqual(rc, 1)
        self.assertIn("ABORTED before deleting anything", err)
        self.assert_nothing_deleted()

    def test_second_collection_snapshot_failure_deletes_neither(self):
        self.fake.snapshot_fails.add(kg.DOCUMENTS)
        rc, _, _ = self.run_main()
        self.assertEqual(rc, 1)
        self.assert_nothing_deleted()

    def test_snapshot_http_error_aborts(self):
        orig = self.fake.__call__

        def boom(method, path, **kw):
            if path.split("?")[0].endswith("/snapshots"):
                raise RuntimeError("HTTP 500 from snapshot")
            return orig(method, path, **kw)

        kg._q = boom
        rc, _, _ = self.run_main()
        self.assertEqual(rc, 1)
        self.assert_nothing_deleted()

    def test_count_mismatch_aborts(self):
        # Qdrant claims one more point than the scroll returned: a short export.
        self.fake.count_skew[kg.ENTITIES] = 1
        rc, _, err = self.run_main()
        self.assertEqual(rc, 1)
        self.assertIn(f"exported {N_ENTITIES} points but Qdrant holds {N_ENTITIES + 1}", err)
        self.assert_nothing_deleted()

    def test_export_write_failure_aborts(self):
        with mock.patch.object(reembed.os, "fsync", side_effect=OSError(28, "No space left on device")):
            rc, _, err = self.run_main()
        self.assertEqual(rc, 1)
        self.assertIn("No space left on device", err)
        self.assert_nothing_deleted()

    def test_truncated_scroll_aborts(self):
        # A _scroll that reads one page only -- the original bug -- must be caught
        # by the count check rather than reaching the delete.
        with mock.patch.object(kg, "_scroll",
                               side_effect=lambda c, f, with_vector=False:
                               [p["payload"] for p in list(self.fake.cols[c].values())[:1000]]):
            rc, _, _ = self.run_main()
        self.assertEqual(rc, 1)
        self.assert_nothing_deleted()


if __name__ == "__main__":
    unittest.main()
