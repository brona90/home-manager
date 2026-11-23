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


def exchange(*lines: str) -> tuple[list[dict], subprocess.CompletedProcess]:
    """Feed raw lines to a fresh server; return every reply it wrote, in order.

    The last line is always a ping with id "alive", and the test asserts it was
    answered: a server that crashed on an earlier line cannot answer it.
    """
    stdin = "\n".join(lines + ('{"jsonrpc":"2.0","id":"alive","method":"ping"}',)) + "\n"
    proc = subprocess.run(
        [SERVER], input=stdin, capture_output=True, text=True, timeout=30,
        env={"EMACSCLIENT": "/nonexistent/emacsclient", "PATH": "/nonexistent"},
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
        self.assertEqual(len(replies[0]["result"]["tools"]), 4)


if __name__ == "__main__":
    SERVER = sys.argv.pop(1)
    unittest.main()
