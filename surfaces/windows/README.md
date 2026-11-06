# The guide window (WSL + Windows only)

A small always-on-top bubble that opens the onboarding guide in a window instead of a terminal.
It is **a surface, not the product** — the same guide runs in the terminal, and nothing here is
required for setup to work.

```
surfaces/windows/
  guide-bridge.py       WSL side: HTTP on 127.0.0.1:8765, wraps `hermes -p guide chat`
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
| drag the bubble | it moves — a drag is not a click |
| **X** on the panel | **collapses to the bubble** (does not quit) |
| right-click the bubble | Quit |
| `Enter` in the box | send · `Shift+Enter` newline |

Closing the panel leaves the bubble, because a chat head that vanishes when you close it is a bug.
To get it back after a real Quit, run `run-guide-window.cmd` again — or just `guide` in a terminal.

## Troubleshooting

- **A reply arrives as "(no answer — is guide-bridge.py running…)"** — the bridge is down. Start it,
  then check `curl http://127.0.0.1:8765/health` from WSL.
- **Nothing appears at all** — run the window from a terminal (drop `-WindowStyle Hidden`) to see the
  PowerShell error.
- **Garbled characters where an em dash should be** (`â€”`) — the `.ps1` lost its UTF-8 BOM. Windows PowerShell 5.1 reads
  `.ps1` as ANSI without one, and every em dash breaks the parse. Keep the BOM.
- **The window is on the wrong monitor** — it anchors to the primary work area; drag it once, it stays.

## Not done yet

- No history restore: reopening starts a fresh transcript (the session on the bridge side persists, so
  the guide still remembers the conversation).
- No streaming: the reply appears when the turn completes (~5–20 s). A typing indicator covers it.
- macOS and native Linux have no equivalent surface; they use the terminal.
