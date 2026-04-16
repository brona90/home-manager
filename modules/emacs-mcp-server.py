#!/usr/bin/env python3
"""MCP server exposing Emacs functions to Claude Code via emacsclient.

Implements the Model Context Protocol (MCP) over stdio with no external
dependencies — only the Python 3 standard library.

Tools provided:
  emacs_eval        — evaluate arbitrary Emacs Lisp
  emacs_show_diff   — trigger 3-way ediff (HEAD vs pre-edit vs current)
  emacs_open_file   — visit a file, optionally at a line
  emacs_notify      — display a message in the minibuffer

Requires: Emacs daemon running with emacsclient accessible on $PATH.
"""

import json
import os
import subprocess
import sys

# ---------------------------------------------------------------------------
# MCP protocol helpers
# ---------------------------------------------------------------------------

PROTOCOL_VERSION = "2024-11-05"

SERVER_INFO = {
    "name": "emacs",
    "version": "1.0.0",
}

TOOLS = [
    {
        "name": "emacs_eval",
        "description": (
            "Evaluate an Emacs Lisp expression via emacsclient and return "
            "the printed result. Use this for any Emacs interaction not "
            "covered by a dedicated tool."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "expression": {
                    "type": "string",
                    "description": "Elisp expression to evaluate",
                },
            },
            "required": ["expression"],
        },
    },
    {
        "name": "emacs_show_diff",
        "description": (
            "Open a 3-way ediff in the user's Emacs frame showing "
            "git HEAD vs the pre-edit snapshot vs the file on disk. "
            "Call this after editing a file so the user can review your "
            "changes interactively."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "file_path": {
                    "type": "string",
                    "description": "Absolute path to the edited file",
                },
            },
            "required": ["file_path"],
        },
    },
    {
        "name": "emacs_open_file",
        "description": (
            "Open a file in the user's Emacs frame, optionally jumping "
            "to a specific line."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "file_path": {
                    "type": "string",
                    "description": "Path to the file to open",
                },
                "line": {
                    "type": "integer",
                    "description": "Line number to jump to (1-indexed, optional)",
                },
            },
            "required": ["file_path"],
        },
    },
    {
        "name": "emacs_notify",
        "description": (
            "Display a message in the Emacs minibuffer. Use this to "
            "notify the user of important status updates while you work."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": "Message to display",
                },
            },
            "required": ["message"],
        },
    },
]


def _log(msg: str) -> None:
    """Write a debug line to stderr (visible in Claude Code diagnostics)."""
    print(f"[emacs-mcp] {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Stdio transport: Content-Length framed JSON-RPC
# ---------------------------------------------------------------------------


def _read_message() -> dict | None:
    """Read one newline-delimited JSON-RPC message from stdin."""
    while True:
        line = sys.stdin.readline()
        if not line:
            return None  # EOF
        line = line.strip()
        if not line:
            continue  # skip blank lines
        return json.loads(line)


def _send_message(msg: dict) -> None:
    """Write one newline-delimited JSON-RPC message to stdout."""
    sys.stdout.write(json.dumps(msg))
    sys.stdout.write("\n")
    sys.stdout.flush()


def _result(msg_id, result: dict) -> None:
    _send_message({"jsonrpc": "2.0", "id": msg_id, "result": result})


def _error(msg_id, code: int, message: str) -> None:
    _send_message(
        {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}
    )


# ---------------------------------------------------------------------------
# emacsclient wrapper
# ---------------------------------------------------------------------------

_EMACSCLIENT = os.environ.get("EMACSCLIENT", "emacsclient")


def _elisp_escape(s: str) -> str:
    """Escape a string for embedding inside an elisp double-quoted string."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def _run_elisp(expression: str) -> tuple[str, bool]:
    """Run an elisp expression via emacsclient --eval.

    Returns (output, success).
    """
    try:
        result = subprocess.run(
            [_EMACSCLIENT, "--eval", expression],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode != 0:
            stderr = result.stderr.strip()
            return (stderr or "emacsclient returned non-zero", False)
        return (result.stdout.strip(), True)
    except FileNotFoundError:
        return (
            "emacsclient not found — is the Emacs daemon running? "
            "Start it with: systemctl --user start emacs",
            False,
        )
    except subprocess.TimeoutExpired:
        return ("emacsclient timed out after 15 s", False)
    except Exception as exc:
        return (str(exc), False)


# ---------------------------------------------------------------------------
# Tool handlers
# ---------------------------------------------------------------------------


def _handle_emacs_eval(arguments: dict) -> dict:
    expression = arguments.get("expression", "")
    if not expression:
        return {
            "content": [{"type": "text", "text": "Error: expression is required"}],
            "isError": True,
        }
    output, ok = _run_elisp(expression)
    return {
        "content": [{"type": "text", "text": output}],
        "isError": not ok,
    }


def _handle_emacs_show_diff(arguments: dict) -> dict:
    file_path = arguments.get("file_path", "")
    if not file_path:
        return {
            "content": [{"type": "text", "text": "Error: file_path is required"}],
            "isError": True,
        }
    abs_path = os.path.abspath(file_path)
    escaped = _elisp_escape(abs_path)

    # For manual invocation, diff HEAD vs disk
    elisp = f"""(let* ((before (with-temp-buffer
                          (let ((default-directory (string-trim (shell-command-to-string "git rev-parse --show-toplevel"))))
                            (call-process "git" nil t nil "show" (concat "HEAD:" (file-relative-name "{escaped}" default-directory)))
                            (buffer-string))))
                 (after (with-temp-buffer (insert-file-contents "{escaped}") (buffer-string))))
              (claude-diff-show "{escaped}" before after)
              "Opened diff for {escaped}")"""

    output, ok = _run_elisp(elisp)
    return {
        "content": [{"type": "text", "text": output}],
        "isError": not ok,
    }


def _handle_emacs_open_file(arguments: dict) -> dict:
    file_path = arguments.get("file_path", "")
    if not file_path:
        return {
            "content": [{"type": "text", "text": "Error: file_path is required"}],
            "isError": True,
        }
    abs_path = os.path.abspath(file_path)
    line = arguments.get("line")

    args = [_EMACSCLIENT, "-n"]
    if line:
        args.append(f"+{line}")
    args.append(abs_path)

    try:
        subprocess.run(args, check=True, timeout=5)
        loc = f"{abs_path}:{line}" if line else abs_path
        return {"content": [{"type": "text", "text": f"Opened {loc}"}]}
    except Exception as exc:
        return {
            "content": [{"type": "text", "text": f"Error: {exc}"}],
            "isError": True,
        }


def _handle_emacs_notify(arguments: dict) -> dict:
    message = arguments.get("message", "")
    if not message:
        return {
            "content": [{"type": "text", "text": "Error: message is required"}],
            "isError": True,
        }
    escaped = _elisp_escape(message)
    output, ok = _run_elisp(f'(message "{escaped}")')
    return {
        "content": [{"type": "text", "text": output}],
        "isError": not ok,
    }


_HANDLERS = {
    "emacs_eval": _handle_emacs_eval,
    "emacs_show_diff": _handle_emacs_show_diff,
    "emacs_open_file": _handle_emacs_open_file,
    "emacs_notify": _handle_emacs_notify,
}


# ---------------------------------------------------------------------------
# MCP request dispatcher
# ---------------------------------------------------------------------------


def _handle_request(msg: dict) -> None:
    method = msg.get("method", "")
    msg_id = msg.get("id")
    params = msg.get("params", {})

    # --- Notifications (no id) ----
    if msg_id is None:
        # notifications/initialized — acknowledge, nothing to respond
        _log(f"notification: {method}")
        return

    # --- Requests (have id) ----
    if method == "initialize":
        _result(
            msg_id,
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": SERVER_INFO,
            },
        )
    elif method == "tools/list":
        _result(msg_id, {"tools": TOOLS})
    elif method == "tools/call":
        tool_name = params.get("name", "")
        arguments = params.get("arguments", {})
        handler = _HANDLERS.get(tool_name)
        if handler is None:
            _error(msg_id, -32601, f"Unknown tool: {tool_name}")
        else:
            _log(f"tools/call {tool_name}")
            try:
                result = handler(arguments)
            except Exception as exc:
                result = {
                    "content": [{"type": "text", "text": f"Internal error: {exc}"}],
                    "isError": True,
                }
            _result(msg_id, result)
    else:
        _error(msg_id, -32601, f"Method not found: {method}")


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------


def main() -> None:
    _log("starting")
    while True:
        msg = _read_message()
        if msg is None:
            _log("stdin closed, exiting")
            break
        _handle_request(msg)


if __name__ == "__main__":
    main()
