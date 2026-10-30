"""MCP stdio handshake probe, run by checks/mcp-servers.nix inside the build sandbox.

usage: mcp-handshake.py NAME TIMEOUT_SECONDS ARGV...

Starts ARGV, sends `initialize', `notifications/initialized' and `tools/list',
and exits 0 only if the server answers both requests and lists at least one
tool. On any other outcome it prints a GUARD line and the last lines of the
server's stderr, which is where an ImportError's traceback lands. A bare
"failed" would name nothing; that symptom is what this check exists to replace.

Standard library only, and run with `python3 -I', so it cannot pick up anything
from the server's environment or from the current directory.

Raw JSON-RPC rather than the SDK's own client, on purpose. A probe written
against the mcp package would break on the next SDK major version along with
the servers it is meant to report on, and it would not run against the porkbun
and emacs servers, which do not use that package.
"""
import json
import subprocess
import sys
import threading

# A version every server here speaks. emacs-mcp-server.py accepts 2024-11-05
# through 2025-06-18, and the SDK servers negotiate down from anything they know.
PROTOCOL_VERSION = "2025-06-18"


def main() -> int:
    name, timeout, argv = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
    proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    err: list[str] = []
    threading.Thread(target=lambda: err.extend(proc.stderr), daemon=True).start()
    result: dict = {}

    def send(msg: dict) -> None:
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()

    def reply(want: int) -> dict:
        # Skip notifications and log lines a server may emit first; stop at the
        # response carrying the id we asked with.
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            msg = json.loads(line)
            if msg.get("id") == want:
                return msg
        raise EOFError("server closed stdout before answering request %d" % want)

    def converse() -> None:
        try:
            send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": PROTOCOL_VERSION, "capabilities": {},
                "clientInfo": {"name": "mcp-servers-check", "version": "0"}}})
            result["init"] = reply(1)
            send({"jsonrpc": "2.0", "method": "notifications/initialized"})
            send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
            result["tools"] = reply(2)
        except Exception as e:  # reported below, together with the server's stderr
            result["error"] = repr(e)

    # On a thread so that a server that hangs fails at the timeout instead of
    # stalling the build until Nix's own timeout fires, which names nothing.
    t = threading.Thread(target=converse, daemon=True)
    t.start()
    t.join(timeout)
    proc.kill()
    proc.wait()

    tools = ((result.get("tools") or {}).get("result") or {}).get("tools") or []
    if "result" in (result.get("init") or {}) and tools:
        names = [t.get("name", "?") for t in tools]
        shown = " ".join(names[:12]) + (" ..." if len(names) > 12 else "")
        print("mcp handshake: %s lists %d tools: %s" % (name, len(names), shown))
        return 0

    if "error" in result:
        why = result["error"]
    elif t.is_alive():
        why = "no answer within %gs" % timeout
    else:
        why = "unusable answer: %s" % json.dumps(result)[:400]
    out = sys.stderr
    out.write("GUARD: MCP server '%s' did not complete an initialize + tools/list handshake\n" % name)
    out.write("       in the build sandbox: %s\n" % why)
    out.write("       command: %s\n" % " ".join(argv))
    out.write("       server stderr, last 20 lines:\n")
    for line in "".join(err).splitlines()[-20:]:
        out.write("         | %s\n" % line)
    return 1


if __name__ == "__main__":
    sys.exit(main())
