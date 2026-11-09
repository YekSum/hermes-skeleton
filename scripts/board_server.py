#!/usr/bin/env python3
"""Live read-only viewer for the canonical Kanban board (project-manager registry).

Serves the board over loopback so the user can keep a browser tab / desktop-app
preview pane on it and see the CURRENT board without prompting an agent.

- Reads board.md on EVERY request (never caches), so it cannot go stale the way
  the static companion board.html can.
- Renders via project-manager's own render_board.py, so the look never drifts
  from the canonical renderer (single render source, no duplicate logic).
- /board.json exposes the parsed rows for scripts, widgets and future plugins.

Usage:
    python3 board_server.py [--host 127.0.0.1] [--port 9130] [--refresh 15]

Stdlib only. Read-only: never writes to the registry, never runs a model.
"""
from __future__ import annotations

import argparse
import html
import io
import json
import os
import re
import sys
import tempfile
import time
from contextlib import redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

def _default_registry() -> Path:
    """project-manager's registry, resolved from the ACTIVE Hermes home.

    Never hardcode an absolute home: the same script has to run on another machine, and a
    hardcoded path is also what the public repo's publish bar rejects.
    """
    home = Path(os.environ.get("HERMES_HOME") or (Path.home() / ".hermes"))
    return home / "profiles" / "project-manager" / "workspace" / "registry"


REGISTRY = _default_registry()


def set_registry(path: str) -> None:
    """Point the viewer at another registry dir (testing / alternate profiles)."""
    global REGISTRY, BOARD_MD, RENDERER
    REGISTRY = Path(path).expanduser().resolve()
    BOARD_MD = REGISTRY / "board.md"
    RENDERER = REGISTRY / "render_board.py"


BOARD_MD = REGISTRY / "board.md"
RENDERER = REGISTRY / "render_board.py"

COLS = ["id", "task", "owner", "status", "priority", "created", "last_updated", "notes"]


# ---------------------------------------------------------------- parsing ----

def parse_board(text: str) -> list[dict]:
    """Parse board.md tables into rows, tagging each with section + status."""
    rows: list[dict] = []
    section = status = None
    in_notes = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("## "):
            name = s[3:].strip()
            status = None
            in_notes = name.lower() == "notes"
            if not in_notes:
                section = name
            continue
        if s.startswith("### ") and not in_notes:
            status = s[4:].strip()
            continue
        if in_notes:
            continue
        if s.startswith("|") and not set(s) <= set("|-: "):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if not cells or cells[0] == "ID":
                continue
            row = {c: (cells[i] if i < len(cells) else "") for i, c in enumerate(COLS)}
            row["section"] = section or ""
            row["status"] = status or ""
            rows.append(row)
    return rows


# Last complete read, so a rewrite in flight never becomes the board the user sees.
_LAST_GOOD: dict = {"text": None, "mtime": 0.0, "key": None}


def read_board(retries: int = 8, settle: float = 0.05) -> tuple[str, float, bool]:
    """Read board.md so a CONCURRENT REWRITE is never served as a partial board.

    A writer (project-manager, or a delegated child) rewrites the whole file
    non-atomically: truncate, then stream the content out. A read landing inside that window
    sees a partial file -- measured at 27% of polls under a simulated concurrent rewrite,
    returning 0 or 27 rows instead of 31, i.e. a board that never existed.

    Stat-before-and-after the read is NOT enough: a half-written file can rest unchanged for
    milliseconds, so a consistent pair of stats can bracket a torn read (measured: still
    14.7% wrong). The guard is therefore QUIESCENCE -- the file must be unchanged across a
    short window before its content is trusted -- plus a cached last-complete read, which is
    served (flagged stale) if the writer never pauses. A quiet file costs one stat, not a
    sleep: the cache hits whenever the file has not changed since the last good read.

    Returns (text, mtime, stale).
    """
    try:
        st = BOARD_MD.stat()
    except FileNotFoundError:
        return "", 0.0, False
    key = (st.st_mtime_ns, st.st_size)
    if _LAST_GOOD["key"] == key and _LAST_GOOD["text"] is not None:
        return _LAST_GOOD["text"], _LAST_GOOD["mtime"], False   # unchanged: no sleep needed

    best = None                            # best quiescent-but-suspicious read (see below)
    if _LAST_GOOD["text"] is None:
        # Cold start with a writer already in flight: there is no previous complete read to
        # fall back on, so try harder before serving the only answer we have. Bounded, and it
        # only ever costs latency once per process.
        retries = max(retries, 20)
    for _ in range(retries):
        try:
            before = BOARD_MD.stat()
        except FileNotFoundError:
            break
        time.sleep(settle)                 # let any in-flight rewrite finish
        try:
            mid = BOARD_MD.stat()
        except FileNotFoundError:
            break
        if (before.st_mtime_ns, before.st_size) != (mid.st_mtime_ns, mid.st_size):
            continue                       # still being written
        try:
            text = BOARD_MD.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        after = BOARD_MD.stat()
        if (mid.st_mtime_ns, mid.st_size) != (after.st_mtime_ns, after.st_size) or not text.strip():
            continue
        prev = _LAST_GOOD["text"]
        if (prev and len(text) < len(prev) and prev.startswith(text)
                and (time.time() - after.st_mtime) < 2.0):
            # A fresh, SHORTER read that is a strict prefix of the last complete one is a
            # rewrite of the same bytes still in flight -- a truncation that landed on a line
            # boundary ends with a newline and passes every cheap completeness test. The 2 s
            # freshness bound keeps a legitimately shrunk board (rows deleted) from reading as
            # stale forever: the next poll, after the file settles, accepts it.
            continue
        if text.endswith("\n"):
            _LAST_GOOD.update(text=text, mtime=after.st_mtime,
                              key=(after.st_mtime_ns, after.st_size))
            return text, after.st_mtime, False
        # Quiescent but not newline-terminated: a torn write ends mid-line, so keep looking
        # for a complete-looking read and only fall back to this one if none appears. The
        # fallback keeps a legitimately newline-less file from reading as stale forever.
        if best is None:
            best = (text, after.st_mtime, (after.st_mtime_ns, after.st_size))

    if best is not None:
        text, mtime, key = best
        _LAST_GOOD.update(text=text, mtime=mtime, key=key)
        return text, mtime, False

    if _LAST_GOOD["text"] is not None:
        return _LAST_GOOD["text"], _LAST_GOOD["mtime"], True
    # First read ever, with a writer already active: best effort, and say it is stale.
    text = BOARD_MD.read_text(encoding="utf-8", errors="replace")
    return text, BOARD_MD.stat().st_mtime, True


# --------------------------------------------------------------- rendering ----

def render_html() -> tuple[str, float]:
    """Render board.md through the canonical renderer, in-process."""
    if not RENDERER.exists():
        raise FileNotFoundError(f"renderer missing: {RENDERER}")
    sys.path.insert(0, str(RENDERER.parent))
    import importlib

    mod = importlib.import_module(RENDERER.stem)
    importlib.reload(mod)  # pick up edits to the renderer without a restart
    text, mtime, _stale = read_board()   # stable snapshot: the renderer reads board.md itself
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "board.html"
        orig = mod.OUT
        mod.OUT = out
        try:
            with redirect_stdout(io.StringIO()):  # silence "wrote ..."
                mod.main()
            return out.read_text(encoding="utf-8"), mtime
        finally:
            mod.OUT = orig


STATUS_ORDER = ["IN_PROGRESS", "BLOCKED", "NEEDS_REVIEW", "READY_TO_PROMOTE", "PLANNED", "DONE"]


def summary_bar(rows: list[dict], mtime: float, refresh: int) -> str:
    counts: dict[str, int] = {}
    for r in rows:
        counts[r["status"].upper()] = counts.get(r["status"].upper(), 0) + 1
    parts = [f"{s.replace('_', ' ').title()} {counts[s]}" for s in STATUS_ORDER if s in counts]
    openish = sum(v for k, v in counts.items() if k not in {"DONE"})
    age = time.time() - mtime
    if age < 90:
        age_s = "just now"
    elif age < 5400:
        age_s = f"{int(age // 60)} min ago"
    elif age < 172800:
        age_s = f"{int(age // 3600)} h ago"
    else:
        age_s = f"{int(age // 86400)} d ago"
    fresh = time.strftime("%H:%M:%S", time.localtime())
    return (
        '<div id="livedash" style="position:sticky;top:0;z-index:9;display:flex;flex-wrap:wrap;'
        "gap:14px;align-items:baseline;background:#2b3138;color:#fff;border-radius:6px;"
        'padding:10px 14px;margin:0 0 16px;font-size:13px">'
        f'<strong style="font-size:14px">{len(rows)} items &middot; {openish} open</strong>'
        f'<span style="opacity:.85">{" &middot; ".join(parts)}</span>'
        f'<span style="margin-left:auto;opacity:.7">board.md updated {age_s} '
        f"&middot; live read {fresh} &middot; auto-refresh {refresh}s</span>"
        '<a href="/note" style="color:#fff;text-decoration:none;border:1px solid '
        'rgba(255,255,255,.4);border-radius:4px;padding:1px 7px;font-size:12px" '
        'title="Narrow sticky-note view">&#9638; compact</a>'
        "</div>"
    )


# Injected into the wide page (which is render_board.py's output, kept untouched) so the
# Windows host's right-click menu works there too.
HOST_BRIDGE = (
    "<script>(function(){var h=window.chrome&&window.chrome.webview;if(!h)return;"
    "document.addEventListener('contextmenu',function(e){e.preventDefault();"
    "h.postMessage({hermes:'menu'});});"
    "var d=document.getElementById('livedash');var s=d&&d.querySelector('strong');"
    "if(s)h.postMessage({hermes:'counts',text:s.textContent});})();</script>"
)


# ------------------------------------------------------------------ note -----
# The narrow "sticky note" layout, served at /note. Deliberately a SEPARATE render
# from board.html: the canonical board is a wide 8-column table, which is unreadable
# at note width. Same DATA (board.json), different layout -- so the two can differ in
# appearance but never in content.

NOTE_CSS = """
  :root { --ink:#22262b; --muted:#6b7280; --line:#e6e2d5; --paper:#fffdf3; --head:#2b3138; }
  * { box-sizing:border-box; }
  html,body { margin:0; height:100%; }
  body { background:var(--paper); color:var(--ink); font-size:12px; line-height:1.35;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif; }
  #hdr { position:sticky; top:0; z-index:5; background:var(--head); color:#fff;
         padding:6px 8px; display:flex; align-items:center; gap:8px; cursor:move;
         user-select:none; -webkit-user-select:none; }
  #hdr .t { font-weight:700; letter-spacing:.08em; font-size:11px; }
  #hdr .c { opacity:.8; font-size:11px; }
  #hdr .sp { margin-left:auto; }
  #hdr button { cursor:pointer; border:1px solid rgba(255,255,255,.35); background:transparent;
                color:#fff; border-radius:4px; font-size:11px; padding:1px 6px; }
  #hdr button:hover { background:rgba(255,255,255,.15); }
  #off { display:none; background:#7f1d1d; color:#fff; padding:5px 8px; font-size:11px; }
  #off.on { display:block; }
  #body { padding:8px; }
  .sec { margin:0 0 10px; }
  .sec > h2 { margin:0 0 5px; font-size:10px; letter-spacing:.09em; text-transform:uppercase;
              padding:3px 6px; border-radius:4px; background:#eceae0; color:#3c4047; }
  .sec > h2 .n { opacity:.6; float:right; font-weight:400; }
  .sec.s-IN_PROGRESS > h2 { background:#fdf0d5; color:#7a5300; }
  .sec.s-BLOCKED > h2 { background:#fbe0e0; color:#8b1c1c; }
  .sec.s-NEEDS_REVIEW > h2 { background:#ece3fb; color:#4c2c85; }
  .sec.s-READY_TO_PROMOTE > h2 { background:#dcecfb; color:#14507f; }
  .sec.s-DONE > h2 { background:#e2f0e4; color:#1f5c2a; }
  .card { border:1px solid var(--line); background:#fff; border-radius:5px; padding:5px 7px;
          margin:0 0 5px; }
  .card .id { font-weight:700; font-size:11px; }
  .card .tx { margin:1px 0 2px; }
  .card .nt { color:var(--muted); font-size:11px; }
  .meta { color:#8a8f98; font-size:10px; margin-top:2px; }
  .empty { color:var(--muted); font-style:italic; font-size:11px; }
  #ft { color:#9aa0a6; font-size:10px; padding:2px 8px 10px; }
"""

NOTE_JS = """
// Present only when embedded in the Windows sticky-note host (WebView2). The host owns
// the window chrome (drag strip, menu, close), so the page's own header is hidden there
// and its counts are pushed up to that strip instead.
const HOST = (window.chrome && window.chrome.webview) || null;
const STATUS = ["IN_PROGRESS","BLOCKED","NEEDS_REVIEW","READY_TO_PROMOTE","PLANNED","DONE"];
const LABEL = { IN_PROGRESS:"In progress", BLOCKED:"Blocked", NEEDS_REVIEW:"Needs review",
                READY_TO_PROMOTE:"Ready to promote", PLANNED:"Planned", DONE:"Done" };
const esc = s => (s == null ? "" : String(s)).replace(/[&<>"]/g, c =>
  ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;" }[c]));

function render(items) {
  const counts = {};
  items.forEach(i => { const k = (i.status || "").toUpperCase(); counts[k] = (counts[k] || 0) + 1; });
  const openish = items.filter(i => (i.status || "").toUpperCase() !== "DONE").length;
  const cntText = items.length + " items \\u00b7 " + openish + " open";
  document.getElementById("cnt").textContent = cntText;
  if (HOST) HOST.postMessage({ hermes: "counts", text: cntText });
  const body = document.getElementById("body");
  let out = "";
  STATUS.concat(Object.keys(counts).filter(k => !STATUS.includes(k)))
    .forEach(st => {
      const rows = items.filter(i => (i.status || "").toUpperCase() === st);
      if (!rows.length) return;
      out += '<div class="sec s-' + esc(st) + '"><h2>' + esc(LABEL[st] || st) +
             '<span class="n">' + rows.length + "</span></h2>";
      rows.forEach(r => {
        out += '<div class="card"><span class="id">' + esc(r.id) + '</span>' +
               '<div class="tx">' + esc(r.task) + "</div>" +
               (r.notes ? '<div class="nt">' + esc(r.notes) + "</div>" : "") +
               '<div class="meta">' + esc(r.owner || "-") + " \\u00b7 " + esc(r.priority || "") +
               (r.last_updated ? " \\u00b7 " + esc(r.last_updated) : "") + "</div></div>";
      });
      out += "</div>";
    });
  body.innerHTML = out || '<div class="empty">No items on the board.</div>';
}

async function tick() {
  try {
    const r = await fetch("/board.json", { cache: "no-store" });
    if (!r.ok) throw new Error("HTTP " + r.status);
    const d = await r.json();
    render(d.items || []);
    document.getElementById("off").classList.remove("on");
    const t = new Date();
    document.getElementById("ft").textContent = d.stale
      ? "read " + t.toTimeString().slice(0,8) + " \\u00b7 board is being rewritten \\u2014 showing the last complete read"
      : "read " + t.toTimeString().slice(0,8) + " \\u00b7 source board.md";
  } catch (e) {
    const off = document.getElementById("off");
    off.textContent = "viewer unreachable (" + e.message + ") \\u2014 showing last known board";
    off.classList.add("on");
  }
}

// Host bridge. A child HWND swallows the form's mouse events, so anything interactive
// over the page is negotiated by message: the host does the native window move.
if (HOST) {
  HOST.postMessage({ hermes: "host", on: true });
  document.getElementById("hdr").style.display = "none";  // native strip replaces it
  document.addEventListener("contextmenu", ev => {
    ev.preventDefault();
    HOST.postMessage({ hermes: "menu" });
  });
}
const hdr = document.getElementById("hdr");
hdr.addEventListener("mousedown", ev => {
  if (ev.target.closest("button")) return;
  if (HOST) HOST.postMessage({ hermes: "drag" });
});
document.getElementById("expand").addEventListener("click", () => {
  if (HOST) HOST.postMessage({ hermes: "mode", mode: "wide" });
  location.href = "/?from=note";
});

tick();
setInterval(tick, __REFRESH__ * 1000);
"""


def note_page(refresh: int) -> str:
    """Compact, narrow layout of the same board data (see NOTE_CSS rationale)."""
    js = NOTE_JS.replace("__REFRESH__", str(refresh))
    return (
        "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        "<title>Board</title><style>" + NOTE_CSS + "</style></head><body>"
        "<div id=\"hdr\"><span class=\"t\">BOARD</span>"
        "<span class=\"c\" id=\"cnt\">&hellip;</span>"
        "<span class=\"sp\"></span>"
        "<button id=\"expand\" title=\"Open the full board\">&#x26F6; full</button></div>"
        "<div id=\"off\"></div><div id=\"body\"></div>"
        "<div id=\"ft\">connecting&hellip;</div>"
        "<script>" + js + "</script></body></html>"
    )


# ----------------------------------------------------------------- server ----

REFRESH = 15


class Handler(BaseHTTPRequestHandler):
    server_version = "hermes-board/1.0"

    def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, must-revalidate")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _html(self, code: int, text: str):
        self._send(code, text.encode("utf-8"), "text/html; charset=utf-8")

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        try:
            if path in ("/healthz", "/health"):
                self._send(200, b"ok\n", "text/plain; charset=utf-8")
            elif path == "/favicon.ico":
                self._send(204, b"", "image/x-icon")
            elif path == "/board.json":
                text, mtime, stale = read_board()
                payload = {
                    "source": str(BOARD_MD),
                    "mtime": mtime,
                    "stale": stale,
                    "items": parse_board(text),
                }
                self._send(200, json.dumps(payload, indent=2).encode(), "application/json")
            elif path in ("/", "/index.html"):
                text, mtime, _stale = read_board()
                page, mtime = render_html()
                page = page.replace(
                    "<head>",
                    f'<head>\n<meta http-equiv="refresh" content="{REFRESH}">',
                    1,
                )
                bar = summary_bar(parse_board(text), mtime, REFRESH)
                page = page.replace("<body>", f"<body>\n{bar}{HOST_BRIDGE}", 1)
                self._html(200, page)
            elif path == "/note":
                self._html(200, note_page(REFRESH))
            elif path == "/raw":
                text, _m, _s = read_board()
                self._send(200, html.escape(text).encode(), "text/plain; charset=utf-8")
            else:
                self._html(404, "<h1>404</h1><p>Try <a href='/'>/</a> or /board.json</p>")
        except Exception as exc:  # never 500 silently — show the reason
            msg = html.escape(f"{type(exc).__name__}: {exc}")
            self._html(500, f"<h1>board viewer error</h1><pre>{msg}</pre>")

    def log_message(self, fmt, *args):  # quieter journal
        if self.path.split("?")[0] not in ("/healthz", "/health", "/favicon.ico"):
            sys.stderr.write("[board] %s - %s\n" % (self.address_string(), fmt % args))


def main():
    global REFRESH
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=9130)
    ap.add_argument("--refresh", type=int, default=15)
    ap.add_argument("--registry", default=None, help="registry dir (default: project-manager's)")
    a = ap.parse_args()
    REFRESH = a.refresh
    if a.registry:
        set_registry(a.registry)
    if not BOARD_MD.exists():
        sys.exit(f"board not found: {BOARD_MD}")
    srv = ThreadingHTTPServer((a.host, a.port), Handler)
    print(f"[board] live view on http://{a.host}:{a.port} (refresh {a.refresh}s, src {BOARD_MD})", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
