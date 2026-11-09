# The guide window (WSL + Windows only)

A small always-on-top bubble that opens the onboarding guide in a window instead of a terminal.
It is **a surface, not the product** — the same guide runs in the terminal, and nothing here is
required for setup to work.

```
surfaces/windows/
  guide-bridge.py       WSL side: HTTP on 127.0.0.1:8765, wraps `hermes -p guide chat`
  start-bridge.ps1      starts the bridge DETACHED so it survives the launcher exiting
  guide-window.ps1      Windows side: PowerShell + WPF, the bubble and the panel
  run-guide-window.cmd  starts the bridge, then the window
```

## Why two halves

The window is a **Windows program**, and `hermes` lives in WSL. Transparency and always-on-top are
exactly what breaks under WSLg, which is the same reason the pet overlay in this ecosystem is a Windows
program. So the window talks HTTP to a bridge that does the Hermes work.

```
[WPF window] --HTTP--> [guide-bridge.py in WSL] --subprocess--> [hermes -p guide chat --resume]
```

## Run it

```bat
run-guide-window.cmd
```

Or by hand:

```bash
# in WSL
python3 surfaces/windows/guide-bridge.py          # leave it running
```
```powershell
# in Windows
powershell -ExecutionPolicy Bypass -File surfaces\windows\guide-window.ps1
```

## Behaviour

| action | result |
|---|---|
| click the bubble | the panel opens |
| double-click the head | also opens it (same action) |
| right-click the head | menu: **Open guide** · **Quit** |
| drag the bubble | it moves — a drag is not a click |
| **X** on the panel | **collapses to the bubble** (does not quit) |
| `Enter` in the box | send · `Shift+Enter` newline |

Closing the panel leaves the bubble, because a chat head that vanishes when you close it is a bug.
To get it back after a real Quit, run `run-guide-window.cmd` again — or just `guide` in a terminal.

## Troubleshooting

- **"bridge error: Unable to connect to the remote server"** — the bridge isn't running. `start-bridge.ps1`
  prints `bridge: up` or `bridge: FAILED` with the exact command to run by hand. Its output, if it ran at
  all, is in `/tmp/guide-bridge.log`.
- **The bridge dies as soon as the launcher exits** — that is what `nohup … &` inside `wsl.exe` does;
  WSL tears down the session. `start-bridge.ps1` starts a detached process instead.
- **Nothing appears at all** — run the window from a terminal (drop `-WindowStyle Hidden`) to see the
  PowerShell error.
- **Garbled characters where an em dash should be** (`â€”`) — the `.ps1` lost its UTF-8 BOM. Windows PowerShell 5.1 reads
  `.ps1` as ANSI without one, and every em dash breaks the parse. Keep the BOM.
- **The window is on the wrong monitor** — it anchors to the primary work area; drag it once, it stays.

## Not done yet

- No history restore: reopening starts a fresh transcript (the session on the bridge side persists, so
  the guide still remembers the conversation).
- No streaming: the reply appears when the turn completes

---

# The board note (WSL + Windows only)

A Sticky-Notes-style window showing the **live Kanban board**. Same two-halves rule as the guide
window, and the same reason: it must be a native Windows program, so it displays a page that WSL
serves rather than rendering anything itself.

```
[ WebView2 window ] --loopback HTTP--> [ scripts/board_server.py in WSL ] --reads--> [ registry/board.md ]
```

It never calls a model, so looking at the board costs no tokens and no session. The window is a
**dumb frame** around `http://127.0.0.1:<port>/note` — it owns only drag, the context menu, the
view toggle and the window size. That is what stops the note and the board page from ever
disagreeing about content.

```
surfaces/windows/
  board-note.ps1        Windows side: the sticky note (WinForms + WebView2)
  run-board-note.cmd    the only thing to double-click
  install-startup.ps1   logon shortcut (waits for WSL; -Remove to undo)
  fetch-webview2.sh     downloads the WebView2 assemblies (never shipped)
  wv2-selftest.ps1      bounded WebView2 test: open, load, close, exit
  screenshot.ps1        DPI-aware screen capture (how off-screen bugs were found)
  board-note.md         the full write-up, including six traps that each cost a debug cycle
```

## Run it

```bash
# 1. the viewer (WSL) — run it as a user service so it is always there
python3 scripts/board_server.py --port 9130
# 2. the dependency (once)
./surfaces/windows/fetch-webview2.sh
```
```bat
:: 3. the note
surfaces\windows
un-board-note.cmd
```

`board-note.ps1 -ValidateOnly` checks staging + assemblies + environment without opening a window;
`wv2-selftest.ps1 -Seconds 20` opens one, loads a URL and closes itself.

## Behaviour

| action | result |
|---|---|
| drag the dark strip | moves the note; position/size/mode persist across launches |
| right-click anywhere | menu: always on top · full board/note · refresh · reset position · close |
| `full` button | expands to the whole board (real tables); `note` shrinks back |
| viewer down | says so and keeps the last known board; clears itself when the viewer answers |

Not always-on-top by default, deliberately: it stays behind other windows until you raise it.

## Board content is read live, and never torn

The viewer reads `board.md` on **every** request, so it cannot be staler than the file — but a
writer rewrites that file non-atomically (truncate, then write), and a read landing inside that
window sees a *partial* board. Measured against a simulated concurrent writer: **27% of reads
returned a board that never existed** (0 or 27 rows instead of 31).

Two guards fixed it, and each was necessary — stat-before-and-after-the-read alone still left
14.7% wrong, because a half-written file can rest unchanged for milliseconds:

1. **Quiescence** — the file must be unchanged across a short window before its content is trusted.
2. **Last-complete cache** — if the writer never pauses, the previous complete read is served and
   flagged `stale`, so the note says "board is being rewritten" instead of showing a torn one; a
   completeness heuristic (a torn write ends mid-line) breaks the tie.

Result over 10 runs of 300 reads each, under an adversarial rewriter: **0 wrong reads in 9 runs;
one run showed a single torn read**. (Before any guard: 27%. With stat-before-and-after alone:
14.7%.) Quote the distribution, not a single run — that is the honest shape of a race fix, and the
test is re-runnable:
`python3 scripts/board-race.py` prints the truth count, the poll count and the wrong-read rate.
Run it after any change to the read path — the number is the point, and it moved 27% → 14.7% →
zero-in-9-of-10-runs across the three guards (quiescence, last-complete cache, torn-prefix rule). (~5–20 s). A typing indicator covers it.
- macOS and native Linux have no equivalent surface; they use the terminal.
