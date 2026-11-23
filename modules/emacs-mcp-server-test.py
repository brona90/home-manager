"""Protocol tests for emacs-mcp-server.py. Stdlib only; run by the package's
installCheckPhase (modules/emacs-mcp.nix) against the INSTALLED server, so a
regression fails `nix build' and `hms' rather than the first Claude session.

None of these reach emacsclient: they exercise the transport and dispatcher only.
EMACSCLIENT is pointed at a path that does not exist so that a test which did
reach it would fail loudly instead of talking to a real daemon.

Usage: python3 emacs-mcp-server-test.py <path-to-server>
"""
import json
import subprocess
import sys
import unittest

SERVER = None


def exchange(*lines: str, env: dict | None = None) -> tuple[list[dict], subprocess.CompletedProcess]:
    """Feed raw lines to a fresh server; return every reply it wrote, in order.

    The last line is always a ping with id "alive", and the test asserts it was
    answered: a server that crashed on an earlier line cannot answer it.
    `env` is added to a minimal environment. Nothing is inherited, so a
    variable set in the caller's shell cannot open the eval gate by accident.
    """
    stdin = "\n".join(lines + ('{"jsonrpc":"2.0","id":"alive","method":"ping"}',)) + "\n"
    proc = subprocess.run(
        [SERVER], input=stdin, capture_output=True, text=True, timeout=30,
        env={"EMACSCLIENT": "/nonexistent/emacsclient", "PATH": "/nonexistent", **(env or {})},
    )
    replies = [json.loads(ln) for ln in proc.stdout.splitlines() if ln.strip()]
    return replies, proc


class NonObjectMessages(unittest.TestCase):
    def assert_invalid_request_then_alive(self, raw: str):
        replies, proc = exchange(raw)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(len(replies), 2, (replies, proc.stderr))
        err = replies[0]
        self.assertEqual(err["jsonrpc"], "2.0")
        self.assertIsNone(err["id"])
        self.assertEqual(err["error"]["code"], -32600)
        self.assertEqual(replies[1], {"jsonrpc": "2.0", "id": "alive", "result": {}})

    def test_empty_array(self):
        self.assert_invalid_request_then_alive("[]")

    def test_number(self):
        self.assert_invalid_request_then_alive("1")

    def test_string(self):
        self.assert_invalid_request_then_alive('"ping"')

    def test_null(self):
        self.assert_invalid_request_then_alive("null")

    def test_batch_is_refused_not_crashed(self):
        self.assert_invalid_request_then_alive('[{"jsonrpc":"2.0","id":1,"method":"ping"}]')


class OtherShapes(unittest.TestCase):
    def test_parse_error_still_reported(self):
        replies, proc = exchange("{not json")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(replies[0]["error"]["code"], -32700)
        self.assertEqual(replies[1]["id"], "alive")

    def test_non_object_params(self):
        replies, proc = exchange('{"jsonrpc":"2.0","id":7,"method":"tools/list","params":[]}')
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(replies[0]["id"], 7)
        self.assertEqual(replies[0]["error"]["code"], -32602)
        self.assertEqual(replies[1]["id"], "alive")

    def test_null_params_is_fine(self):
        replies, _ = exchange('{"jsonrpc":"2.0","id":8,"method":"tools/list","params":null}')
        self.assertEqual(replies[0]["id"], 8)
        self.assertEqual(len(replies[0]["result"]["tools"]), 3)


LIST = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
CALL_EVAL = ('{"jsonrpc":"2.0","id":2,"method":"tools/call",'
             '"params":{"name":"emacs_eval","arguments":{"expression":"(+ 1 2)"}}}')
OTHERS = {"emacs_show_diff", "emacs_open_file", "emacs_notify"}


class EvalGate(unittest.TestCase):
    """emacs_eval exists only when EMACS_MCP_ALLOW_EVAL is exactly "1".

    EMACSCLIENT points at a missing path, so a call that gets past the gate
    comes back as a tool RESULT with isError set ("emacsclient not found").
    A call the gate refuses comes back as a JSON-RPC ERROR. The two shapes are
    how the tests tell "refused" from "dispatched".
    """

    def assert_closed(self, env):
        replies, proc = exchange(LIST, CALL_EVAL, env=env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        names = {t["name"] for t in replies[0]["result"]["tools"]}
        self.assertEqual(names, OTHERS)
        refused = replies[1]
        self.assertEqual(refused["id"], 2)
        self.assertNotIn("result", refused)
        self.assertEqual(refused["error"]["code"], -32601)
        self.assertIn("EMACS_MCP_ALLOW_EVAL=1", refused["error"]["message"])
        self.assertEqual(replies[2]["id"], "alive")

    def test_unset_is_closed(self):
        self.assert_closed(None)

    def test_only_exactly_1_opens_it(self):
        for v in ("", "0", "true", "yes", " 1", "1 "):
            with self.subTest(value=v):
                self.assert_closed({"EMACS_MCP_ALLOW_EVAL": v})

    def test_set_to_1_is_open(self):
        replies, proc = exchange(LIST, CALL_EVAL, env={"EMACS_MCP_ALLOW_EVAL": "1"})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        names = {t["name"] for t in replies[0]["result"]["tools"]}
        self.assertEqual(names, OTHERS | {"emacs_eval"})
        dispatched = replies[1]
        self.assertEqual(dispatched["id"], 2)
        self.assertNotIn("error", dispatched)
        self.assertTrue(dispatched["result"]["isError"])
        self.assertIn("emacsclient not found", dispatched["result"]["content"][0]["text"])

    def test_other_tools_unaffected_when_closed(self):
        call = ('{"jsonrpc":"2.0","id":3,"method":"tools/call",'
                '"params":{"name":"emacs_notify","arguments":{"message":"hi"}}}')
        replies, _ = exchange(call)
        self.assertNotIn("error", replies[0])  # dispatched; fails only on the missing emacsclient
        self.assertIn("emacsclient not found", replies[0]["result"]["content"][0]["text"])


if __name__ == "__main__":
    SERVER = sys.argv.pop(1)
    unittest.main()
