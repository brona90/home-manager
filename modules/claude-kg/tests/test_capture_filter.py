"""capture_local's secret filter: what it redacts, what it leaves alone, and the
proof that nothing it catches reaches a graph write or the capture log.

Every secret here is generated at run time from a seeded RNG and assembled from
pieces. A literal token in the source would trip secret scanners on push, and
it would also be the very thing this filter exists to keep off disk.
"""
import contextlib
import io
import json
import os
import random
import string
import sys
import tempfile
import unittest
from unittest import mock

import capture_local as cap

RNG = random.Random(20261123)
B62 = string.ascii_letters + string.digits
B64 = B62 + "+/"
BECH32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def rand(alphabet, n):
    return "".join(RNG.choice(alphabet) for _ in range(n))


def age_key():
    return "AGE-SECRET-" + "KEY-1" + rand(BECH32, 58).upper()


def ghp():
    return "gh" + "p_" + rand(B62, 36)


def github_pat():
    return "github" + "_pat_" + rand(B62, 22) + "_" + rand(B62, 59)


def akia():
    return "AK" + "IA" + rand(string.ascii_uppercase + string.digits, 16)


def pem(label="OPENSSH PRIVATE KEY", end=True):
    body = "\n".join(rand(B64, 64) for _ in range(6))
    block = f"-----BEGIN {label}-----\n{body}\n"
    if end:
        block += f"-----END {label}-----"
    return block, body


SECRETS = {
    "age-secret-key": age_key,
    "github-token": ghp,
    "aws-access-key": akia,
}


class Redaction(unittest.TestCase):
    def assert_redacted(self, secret, kind):
        text = f"before {secret} after"
        out, hits = cap.redact(text)
        self.assertNotIn(secret, out)
        self.assertEqual(hits[kind], 1, hits)
        self.assertEqual(out, f"before [REDACTED:{kind}] after")

    def test_age_secret_key(self):
        self.assert_redacted(age_key(), "age-secret-key")

    def test_age_secret_key_lower_case(self):
        self.assert_redacted(age_key().lower(), "age-secret-key")

    def test_github_classic_pat(self):
        self.assert_redacted(ghp(), "github-token")

    def test_github_other_prefixes(self):
        for p in ("gho_", "ghu_", "ghs_", "ghr_"):
            self.assert_redacted(p + rand(B62, 36), "github-token")

    def test_github_fine_grained_pat(self):
        self.assert_redacted(github_pat(), "github-token")

    def test_aws_access_key_id(self):
        self.assert_redacted(akia(), "aws-access-key")

    def test_aws_sts_key_id(self):
        self.assert_redacted("AS" + "IA" + rand(string.ascii_uppercase + string.digits, 16),
                             "aws-access-key")

    def test_anthropic_key(self):
        self.assert_redacted("sk-" + "ant-api03-" + rand(B62 + "-_", 90), "anthropic-key")

    def test_pem_block_replaced_whole(self):
        for label in ("OPENSSH PRIVATE KEY", "RSA PRIVATE KEY", "PRIVATE KEY",
                      "EC PRIVATE KEY", "PGP PRIVATE KEY BLOCK"):
            block, body = pem(label)
            out, hits = cap.redact(f"key:\n{block}\ndone")
            self.assertEqual(out, "key:\n[REDACTED:pem-private-key]\ndone", label)
            self.assertEqual(dict(hits), {"pem-private-key": 1}, label)
            for line in body.splitlines():
                self.assertNotIn(line, out)

    def test_pem_block_without_end_line(self):
        block, body = pem(end=False)
        out, hits = cap.redact("pasted: " + block + "and then the paste was cut off")
        self.assertEqual(out, "pasted: [REDACTED:pem-private-key]")
        self.assertEqual(hits["pem-private-key"], 1)

    def test_high_entropy_aws_secret_style(self):
        self.assert_redacted(rand(B64, 40), "high-entropy-token")

    def test_high_entropy_40_char_base62(self):
        # Fixed seed, so this cannot flake. At 40 chars the measured catch rate
        # is 99.7%, and these draws are all caught.
        for _ in range(50):
            self.assert_redacted(rand(B62, 40), "high-entropy-token")

    def test_high_entropy_catch_rate_at_minimum_length(self):
        # At 32 chars, the shortest the pass looks at, the heuristic is
        # deliberately imperfect (see _looks_random). This pins the rate, not
        # every draw: a change that loosens the rule visibly drops below it.
        draws = [rand(B62, 32) for _ in range(2000)]
        caught = sum(bool(cap.redact(d)[1]) for d in draws)
        self.assertGreaterEqual(caught / len(draws), 0.97, caught)

    def test_high_entropy_jwt_segments(self):
        jwt = ".".join(rand(B62 + "-_", n) for n in (36, 120, 43))
        out, hits = cap.redact(jwt)
        self.assertGreaterEqual(hits["high-entropy-token"], 2)
        self.assertNotIn(jwt.split(".")[1], out)

    def test_several_kinds_in_one_text(self):
        a, g, k = age_key(), ghp(), akia()
        out, hits = cap.redact(f"{a} and {g} and {k} and {g}")
        self.assertEqual(dict(hits), {"age-secret-key": 1, "github-token": 2, "aws-access-key": 1})
        for s in (a, g, k):
            self.assertNotIn(s, out)

    def test_redaction_is_idempotent(self):
        once, _ = cap.redact(f"{ghp()} {rand(B64, 40)}")
        twice, hits = cap.redact(once)
        self.assertEqual(twice, once)
        self.assertFalse(hits)


class LeftAlone(unittest.TestCase):
    """Long strings that are not secrets and are common in these sessions."""

    KEEP = [
        "commit 7b9d8c9555b47feafa767fb559adc0825728fa35 landed",          # git SHA
        "6e6b1f2a-0000-4000-8000-c1a0de000001",                            # UUID
        "/nix/store/0c2kfg4m8v6hq3x9r1dzyl5a7nbwjpis-python3-3.12.8/bin",   # store path
        "fingerprint 4E1F799AA4FF2279EB5A2E6A4F2A7C9E0B1D3C5F",             # GPG fpr
        "/home/gfoster/.config/home-manager/modules/claude-kg/src/kg_server.py",
        "C:/Users/brona/AppData/Local/Programs/Microsoft VS Code/Code.exe",
        "TestCaptureFilterKeepsOrdinaryIdentifiers",
        "Base64EncodedPayloadParser2Factory",                               # mixed classes
        "SessionStartHookTimeoutWindows45Seconds",
        "K8sClusterNodePoolUpgrade20261123Rollout",
        "fix-muse-review-2026-11-ClaudeKgPagingReembed",
        "kg_prompt_recall_hook_timeout_seconds_default",
        "my.claudeCode.sessionStartCommands is a list of attrsets",
        "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p",  # age PUBLIC key
        "https://github.com/brona90/bench/pull/57#issuecomment-1234567890",
        "AKIAISNOTAKEY",                                                    # too short
    ]

    def test_ordinary_text_untouched(self):
        for s in self.KEEP:
            out, hits = cap.redact(s)
            self.assertEqual(out, s, (s, hits))
            self.assertFalse(hits, s)

    def test_known_false_positive(self):
        # Pinned so the trade-off described at _looks_random stays visible. If a
        # better rule keeps this, move it into KEEP.
        self.assertTrue(cap.redact("x86_64-linux-HomeManagerGeneration2026-11-23")[1])


class FilterExtracted(unittest.TestCase):
    def test_drops_items_and_never_logs_the_secret(self):
        g, a, k = ghp(), age_key(), akia()
        data = {
            "entities": [
                {"name": "claude-kg", "type": "project",
                 "observations": ["uses Qdrant", f"token is {g}", "  ", 7]},
                {"name": a, "type": "key", "observations": ["harmless"]},
                {"name": "Deploy", "type": "process", "observations": [f"creds {k}"]},
            ],
            "relations": [
                {"source": "claude-kg", "relation": "uses", "target": "Qdrant"},
                {"source": "claude-kg", "relation": "authenticates-with", "target": g},
            ],
        }
        ents, rels, log = cap.filter_extracted(data)
        self.assertEqual([e["name"] for e in ents], ["claude-kg", "Deploy"])
        self.assertEqual(ents[0]["observations"], ["uses Qdrant"])
        self.assertEqual(ents[1]["observations"], [])
        self.assertEqual(rels, [{"source": "claude-kg", "relation": "uses", "target": "Qdrant"}])
        self.assertEqual(len(log), 4, log)
        blob = "\n".join(log)
        for s in (g, a, k):
            self.assertNotIn(s, blob)
        self.assertIn("dropped observation on entity 'claude-kg' (github-token x1)", blob)
        self.assertIn("dropped entity #1 (name/type matched age-secret-key x1)", blob)
        self.assertIn("dropped relation #1 (github-token x1)", blob)

    def test_clean_input_passes_through(self):
        data = {"entities": [{"name": "A", "type": "t", "observations": ["x"]}],
                "relations": [{"source": "A", "relation": "r", "target": "B"}]}
        ents, rels, log = cap.filter_extracted(data)
        self.assertEqual(ents, data["entities"])
        self.assertEqual(rels, data["relations"])
        self.assertEqual(log, [])

    def test_tolerates_malformed_model_output(self):
        ents, rels, log = cap.filter_extracted({"entities": None, "relations": ["x", 3]})
        self.assertEqual((ents, rels, log), ([], [], []))


def _transcript(path, texts):
    with open(path, "w", encoding="utf-8") as f:
        for i, t in enumerate(texts):
            role = "user" if i % 2 == 0 else "assistant"
            f.write(json.dumps({"type": role, "message": {"role": role, "content": t}}) + "\n")


class EndToEnd(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = os.path.join(tmp.name, "t.jsonl")

    def test_redacts_before_slicing(self):
        # A PEM block straddling the MAX_CHARS cut. Slicing first would keep its
        # tail, with no BEGIN line left for the pattern to anchor on.
        block, body = pem()
        filler = "ordinary words " * ((cap.MAX_CHARS // 15) - 10)
        _transcript(self.path, [block, filler])
        convo, hits = cap._conversation(self.path)
        self.assertEqual(hits["pem-private-key"], 1)
        for line in body.splitlines():
            self.assertNotIn(line, convo)

    def test_no_secret_reaches_ollama_a_write_or_the_log(self):
        g, k, a = ghp(), akia(), age_key()
        _transcript(self.path, [f"my token is {g} and the key id is {k} " + "padding " * 40,
                                "noted, I will not store it"])
        # The model "leaks" a secret it was never shown (the transcript was
        # redacted); the post-extraction pass must still drop it.
        model_out = {"entities": [{"name": "Bench", "type": "project",
                                   "observations": ["publishes hourly", f"key {a}"]}],
                     "relations": [{"source": "Bench", "relation": "uses", "target": "R2"}]}
        sent = {}

        def fake_post(url, **kw):
            sent["body"] = kw["json"]
            r = mock.Mock()
            r.json.return_value = {"message": {"content": json.dumps(model_out)}}
            return r

        writes = []
        out = io.StringIO()
        with mock.patch.object(cap.httpx, "post", fake_post), \
             mock.patch.object(cap.kg, "_retrieve_entity", return_value=None), \
             mock.patch.object(cap.kg, "kg_upsert_entity",
                               side_effect=lambda *a, **kw: writes.append(("upsert", a, kw))), \
             mock.patch.object(cap.kg, "kg_add_observations",
                               side_effect=lambda *a, **kw: writes.append(("add", a, kw))), \
             mock.patch.object(cap.kg, "kg_relate",
                               side_effect=lambda *a, **kw: writes.append(("relate", a, kw))), \
             mock.patch.object(sys, "argv", ["kg-capture", self.path, "/src"]), \
             contextlib.redirect_stdout(out):
            self.assertEqual(cap.main(), 0)

        prompt = json.dumps(sent["body"])
        self.assertNotIn(g, prompt)
        self.assertNotIn(k, prompt)
        self.assertIn("[REDACTED:github-token]", prompt)
        self.assertEqual(writes, [("upsert", ("Bench", "project", ["publishes hourly"]), {"source": "/src"}),
                                  ("relate", ("Bench", "uses", "R2"), {})])
        log = out.getvalue()
        for s in (g, k, a):
            self.assertNotIn(s, log)
            self.assertNotIn(s, repr(writes))
        self.assertIn("redacted from transcript before extraction: aws-access-key x1, github-token x1", log)
        self.assertIn("dropped observation on entity 'Bench' (age-secret-key x1)", log)


if __name__ == "__main__":
    unittest.main()
