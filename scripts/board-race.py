#!/usr/bin/env python3
"""Does a concurrent rewrite of board.md ever make the viewer serve a WRONG board?

The viewer reads board.md on every request, and a writer (project-manager, or a delegated
child) rewrites the whole file non-atomically: truncate, then write. If a read lands inside
that window it sees a partial file -- fewer rows, or a truncated last row -- and the note
would render a board that never existed.

This drives the real server against a throwaway registry and counts inconsistent responses.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # board_server.py lives beside this
from board_server import _default_registry  # noqa: E402

REG = _default_registry()
TMP = Path(os.environ.get("BOARD_RACE_TMP") or tempfile.mkdtemp(prefix="board-race-"))
PORT = 9132
N_WRITES = 40
N_POLLS = 300


def rows_in(text: str) -> int:
    return sum(1 for ln in text.splitlines() if ln.startswith("| ") and not ln.startswith("| ID") and set(ln.strip()) - set("|-: "))


def main() -> int:
    shutil.rmtree(TMP, ignore_errors=True)
    TMP.mkdir(parents=True)
    shutil.copy(REG / "board.md", TMP / "board.md")
    shutil.copy(REG / "render_board.py", TMP / "render_board.py")
    truth = rows_in((TMP / "board.md").read_text())
    print(f"truth: {truth} rows")

    srv = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve().parent / "board_server.py"),
         "--port", str(PORT), "--registry", str(TMP)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(2)
    stop = threading.Event()
    counts: list[int] = []

    def writer():
        body = (TMP / "board.md").read_text()
        for i in range(N_WRITES):
            if stop.is_set():
                break
            # the shape a real writer has: truncate, then stream the content out
            with open(TMP / "board.md", "w", encoding="utf-8") as fh:
                for chunk in (body[: len(body) // 2], body[len(body) // 2 :]):
                    fh.write(chunk)
                    fh.flush()
                    time.sleep(0.004)          # widen the window a read can land in
            time.sleep(0.01)

    t = threading.Thread(target=writer, daemon=True)
    t.start()
    try:
        for _ in range(N_POLLS):
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/board.json", timeout=5) as r:
                counts.append(len(json.load(r)["items"]))
    except Exception as exc:  # noqa: BLE001
        print("poll error:", exc)
    stop.set()
    t.join(timeout=5)
    srv.terminate()

    bad = [c for c in counts if c != truth]
    print(f"polls: {len(counts)}   wrong-row-count responses: {len(bad)} ({100*len(bad)/max(1,len(counts)):.1f}%)")
    if bad:
        print("observed wrong counts:", sorted(set(bad))[:10])
    return 0


if __name__ == "__main__":
    sys.exit(main())
