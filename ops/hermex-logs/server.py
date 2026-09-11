#!/usr/bin/env python3
"""Hermex Plus Logs Server — standalone ingest endpoint.

Receives diagnostic events (freezes, errors, lifecycle) from the Hermex Plus
iOS app, appends them to a JSON-lines file. Zero dependencies (stdlib only),
same pattern as the scheduled-endpoint.

Port: 8912
Storage: ~/.hermes/hermex-logs.jsonl  (one JSON object per line, append-only)

Accept a single event object or a batch array:
  POST /webhook/hermex-logs
  {"type":"freeze","ts":1755000000,"durationMs":3200,"screen":"ChatView","message":"main thread blocked"}
or
  POST /webhook/hermex-logs
  [ {...}, {...} ]
"""

import json
import os
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

LOG_FILE = Path.home() / ".hermes" / "hermex-logs.jsonl"
PORT = 8912

# Rotation: the file is append-only and the app pushes events continuously, so
# without a cap it grows forever. When it passes MAX_LOG_BYTES the file is
# rewritten keeping only the last KEEP_LINES lines. Rotation runs on ingest
# (cheap: a stat call per event) and is done by rewriting to a temp file and
# renaming, so a crash mid-rotation cannot leave a truncated log in place.
MAX_LOG_BYTES = 20 * 1024 * 1024   # rotate at 20 MB
KEEP_LINES = 50_000                # keep roughly the newest half

# Event types the watchdog treats as actionable (everything else is noise).
INTERESTING_TYPES = {"freeze", "error", "crash"}

_write_lock = None  # set in main()


def _rotate_if_needed() -> None:
    """Trim the log when it exceeds MAX_LOG_BYTES, keeping the newest lines.

    Runs under the caller's _write_lock. Rewrites to a sibling temp file and
    os.replace()s it into place: readers (the watchdog, /health) either see the
    old complete file or the new complete file, never a half-written one.
    """
    try:
        if not LOG_FILE.exists() or LOG_FILE.stat().st_size <= MAX_LOG_BYTES:
            return
        with open(LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        kept = lines[-KEEP_LINES:]
        tmp = LOG_FILE.with_suffix(".jsonl.rotating")
        with open(tmp, "w", encoding="utf-8") as f:
            f.writelines(kept)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, LOG_FILE)
    except Exception:
        # Rotation is housekeeping — never let it break ingestion.
        pass


def append_event(event: dict) -> None:
    """Append one event as a JSON line. Always stamps a server receive time."""
    if not isinstance(event, dict):
        return
    # Server-side receive timestamp — client ts may be absent or wrong.
    event = dict(event)
    event["receivedAt"] = int(time.time())
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with _write_lock:
        _rotate_if_needed()
        with open(LOG_FILE, "a") as f:
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
            f.flush()


class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        # Deliberately NO-OP. The default writes every request to stdout, and
        # when stdout is a pipe nobody reads (or a full pipe buffer), that
        # print BLOCKS the handler — and since HTTPServer is single-threaded,
        # one blocked handler freezes the whole ingest endpoint for every
        # request (POST and /health alike). This is exactly why
        # ~/.hermes/hermex-logs.jsonl stopped growing on 27.08 18:37. Kite the
        # request log off to logging or drop it entirely; never print to a
        # piped stdout inside a request handler.
        pass

    def handle_one_request(self):
        """Never let a client disconnect take the whole server down.

        A client that goes away mid-response (app backgrounded, network drop)
        makes wfile.write() raise BrokenPipeError/ConnectionResetError. Unhandled,
        that propagated out of the handler, through socketserver, and killed the
        process — the ingest endpoint was dead for two weeks from exactly this.
        The socket-level errors are the client's business, not ours: log and move on.
        """
        try:
            super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            self.close_connection = True

    def _json(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # Client vanished before we finished replying. Nothing to do.
            self.close_connection = True

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if not length:
            return None
        return json.loads(self.rfile.read(length))

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            count = 0
            if LOG_FILE.exists():
                try:
                    with open(LOG_FILE) as f:
                        count = sum(1 for _ in f)
                except Exception:
                    pass
            return self._json({"status": "ok", "events": count})
        self._json({"error": "not found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/webhook/hermex-logs":
            return self._json({"error": "not found"}, 404)

        try:
            data = self._read_body()
        except Exception:
            return self._json({"ok": False, "error": "invalid JSON"}, 400)

        if isinstance(data, list):
            for item in data:
                append_event(item)
            return self._json({"ok": True, "received": len(data)})

        if isinstance(data, dict):
            append_event(data)
            return self._json({"ok": True, "received": 1})

        return self._json({"ok": False, "error": "expected object or array"}, 400)


def main():
    global _write_lock
    import threading
    _write_lock = threading.Lock()
    # NEVER let stdout/stderr go to a piped destination: a request handler that
    # prints to a full/unread pipe blocks, and a single-threaded HTTPServer then
    # hangs for every request. Redirect to a log file (appended, line-buffered)
    # so any print/exception is durable and never blocks ingestion.
    log_path = Path.home() / ".hermes" / "hermex-logs-server.log"
    try:
        log_handle = open(log_path, "a", buffering=1)
        sys.stdout = log_handle
        sys.stderr = log_handle
    except Exception:
        # Fall back to devnull if the log can't be opened — never a pipe.
        null_handle = open(os.devnull, "w")
        sys.stdout = null_handle
        sys.stderr = null_handle
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[hermex-logs] listening on :{PORT} -> {LOG_FILE}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
