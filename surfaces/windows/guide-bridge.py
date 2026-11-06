#!/usr/bin/env python3
"""guide-bridge — the WSL half of the chat-head window.

A tiny HTTP server so a Windows program can talk to the guide profile without knowing anything about
Hermes, sessions, or the filesystem layout. Loopback only.

    GET  /health          -> {"ok": true, "profile": "guide", "session": "..."}
    POST /chat            -> {"text": "..."} => {"reply": "..."}
    POST /reset           -> forget the current session (next /chat starts a new interview)

Why a bridge and not "the window shells out to hermes": the window is a Windows program and cannot run
`hermes` — that binary lives in WSL. Keeping the process boundary here also means the window can be
replaced (or ported to a mac) without touching the mechanism.

Run:  python3 guide-bridge.py [--port 8765] [--bind 127.0.0.1]
Env:  GUIDE_PROFILE (default: guide), HERMES_HOME (ecosystem root)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path(os.environ.get("HERMES_HOME") or (Path.home() / ".hermes"))
PROFILE = os.environ.get("GUIDE_PROFILE", "guide")
STATE = HOME / "profiles" / PROFILE / "state.db"
SESSION_FILE = HOME / "cache" / "guide-bridge-session"
LOCK = threading.Lock()
TIMEOUT_S = 300


def current_session() -> str:
    try:
        return SESSION_FILE.read_text().strip()
    except OSError:
        return ""


def remember_session(sid: str) -> None:
    SESSION_FILE.parent.mkdir(parents=True, exist_ok=True)
    SESSION_FILE.write_text(sid)


def last_reply(sid: str) -> str:
    """Read the assistant's answer out of the session store — the CLI prints no reply text."""
    if not STATE.exists():
        return ""
    try:
        con = sqlite3.connect(f"file:{STATE}?mode=ro", uri=True)
        row = con.execute(
            "select content from messages where session_id=? and role='assistant' "
            "and content is not null and content!='' order by id desc limit 1",
            (sid,),
        ).fetchone()
        con.close()
        return (row[0] or "").strip() if row else ""
    except sqlite3.Error:
        return ""


def ask(text: str) -> str:
    with LOCK:  # one turn at a time; the guide is a conversation, not a queue
        sid = current_session()
        cmd = ["hermes", "-p", PROFILE, "chat"]
        if sid:
            cmd += ["--resume", sid]
        cmd += ["-q", text]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S)
        except subprocess.TimeoutExpired:
            return "(the guide took too long — it may still be working; try again in a moment)"
        out = (proc.stdout or "") + (proc.stderr or "")
        m = re.search(r"Session:\s+(local-[0-9a-f]+)", out)
        if m:
            sid = m.group(1)
            remember_session(sid)
        reply = last_reply(sid) if sid else ""
        if not reply:
            # Never return silence: a blank window looks like a crash.
            tail = " ".join(out.split())[-400:]
            reply = f"(no answer returned) {tail}" if tail else "(no answer returned)"
        return reply


class Handler(BaseHTTPRequestHandler):
    server_version = "guide-bridge/1.0"

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.startswith("/health"):
            self._json(200, {"ok": True, "profile": PROFILE, "session": current_session()})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "body must be JSON"})
            return

        if self.path.startswith("/reset"):
            try:
                SESSION_FILE.unlink()
            except OSError:
                pass
            self._json(200, {"ok": True})
            return

        if self.path.startswith("/chat"):
            text = (data.get("text") or "").strip()
            if not text:
                self._json(400, {"error": "text is required"})
                return
            self._json(200, {"reply": ask(text)})
            return

        self._json(404, {"error": "not found"})

    def log_message(self, format: str, *args) -> None:  # noqa: A002 — base class name
        pass  # keep the console quiet


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--bind", default="127.0.0.1")
    args = ap.parse_args()

    if not (HOME / "profiles" / PROFILE).exists():
        print(f"warning: profile '{PROFILE}' not found under {HOME} — run ./bootstrap.sh first",
              file=sys.stderr)
    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"guide-bridge listening on http://{args.bind}:{args.port}  (profile: {PROFILE})")
    print("  GET /health · POST /chat {\"text\": \"...\"} · POST /reset")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
