# Board note — a desktop sticky note for the Hermes Kanban board

A borderless window that sits on the Windows desktop showing the **live** Hermes Kanban board
(the canonical `board.md` that project-manager owns). It never calls a model: it reads the
viewer in WSL over loopback, so looking at the board costs nothing and is never out of date.

```
[ WSL ]  hermes-board.service  ──  http://127.0.0.1:9130/note   (narrow layout)
        board_server.py         ──  http://127.0.0.1:9130/       (full board)
                                          │  WSL2 localhost forwarding
[ Windows ]  board-note.ps1 (WebView2) ───┘  a dumb frame: drag, menu, resize
```

The Windows half renders **nothing** itself — it displays what the WSL viewer serves. That is
why the note can never disagree with the board page about content.

## Use

- **Start it:** double-click `run-board-note.cmd` (or it starts at login if you ran
  `install-startup.ps1`).
- **Move it:** drag the dark strip at the top.
- **Right-click** anywhere on the window for the menu:
  - *Always on top* — flips it over other windows. **Off by default**: the note sits behind
    windows until you bring it forward, so a maximised app hides it.
  - *Full board / note*, *Refresh*, *Compact note*, *Open full board*, *Open in browser*
  - *Reset position* — if it ends up somewhere awkward
  - *Close note*
- **`full` button** — expands the note into the wide board (real tables); `note` shrinks it back.
  Each view remembers its own size and place.
- **Viewer offline?** A red bar says so and it keeps the last known board. It retries every
  15 s and clears itself when the viewer answers. It will not silently show you a stale board
  as if it were current.

## Files

| File | Role |
|---|---|
| `board-note.ps1` | The window. WinForms + WebView2, DPI-aware, borderless. |
| `run-board-note.cmd` | The only thing a Windows user needs to run (double-clickable). |
| `install-startup.ps1` | Adds/removes the logon shortcut (`-Remove` to undo). Waits for WSL before launching, and is single-instance. |
| `fetch-webview2.sh` | Downloads the three WebView2 assemblies (they are never shipped). |
| `screenshot.ps1` | DPI-aware screen capture — for verification, and it is why off-screen bugs were findable. |
| `wv2-selftest.ps1` | Bounded WebView2 self-test (`-Seconds 20`): opens, loads a URL, closes, exits. Use before blaming the app. |
| `webview2/` | The three WebView2 assemblies (staged to `%LOCALAPPDATA%\hermes-board-note` at run time). |

State lives in `%LOCALAPPDATA%\hermes-board-note\` — `state.json` (position/size/mode/topmost),
`note.log` (what the host did), `profile\` (WebView2 user data), `webview2\` (staged DLLs).

## Why it looks like this — six things that cost a debugging cycle each

1. **The WebView2 assemblies cannot be loaded from a UNC path.** Running this script from
   `\\wsl.localhost\...` is fine, but `Add-Type -Path` on the DLLs fails with
   `0x80131515 Operation is not supported`. They are copied to `%LOCALAPPDATA%` and loaded
   from there. This is why the script lives on the WSL filesystem but stages its dependency.
2. **`EnsureCoreWebView2Async($null)` kills the process silently** — exit code 2, no exception,
   nothing in the event log. It derives its user-data folder next to `powershell.exe`
   (System32, not writable). Fix: build an explicit `CoreWebView2Environment` with a folder you
   own, *before* any UI exists (blocking there is safe — no message pump yet).
3. **The WPF WebView2 control dies the same way.** The WinForms control works.
4. **The window must start on screen.** An off-screen (`-10000`) window stalls initialisation
   forever, with no error.
5. **The process must be DPI-aware.** On a scaled display a DPI-unaware window is
   bitmap-stretched (blurry) *and* reports a virtualised screen size (1280×720 for a 1920×1080
   panel), so placement maths and any screenshot land in the wrong coordinate space.
6. **`NavigationCompleted` has no `Uri` property** (only `NavigationStarting` does), so a mode
   switch keyed on the completed event silently never fires. The target is captured in
   `NavigationStarting`.

Plus two operational traps: **never invoke the `.cmd` from a tool call and wait** — `cmd /c` on a
`.cmd` that `start`s a GUI process blocks until that window closes (use `Start-Process`); and
**`pkill -f <script>.py`** kills the shell you are typing in, because the pattern matches your
own command line.

## Wiring it into a fresh machine

This ships in the public skeleton under `surfaces/windows/` (the whole set is a `copy` class
there, so the repo is byte-for-byte this directory), with the viewer as
`scripts/board_server.py`.

1. Run the viewer as a user service — `hermes-board.service`, loopback `9130` (linger on, or
   it dies with the login session).
2. `./fetch-webview2.sh` — downloads the three WebView2 assemblies into `webview2/`. They are
   **not shipped**: third-party binaries belong in a fetch step, not a public repo. It also
   prints the registry check for the WebView2 *runtime*, which must already be on the machine.
3. `install-startup.ps1` for the logon shortcut (`-Remove` to undo). It derives its own path, so
   it works from a repo checkout as well as an installed copy.
4. Verify before believing anything: `wv2-selftest.ps1 -Seconds 20` (bounded WebView2 test),
   then `board-note.ps1 -ValidateOnly` (staging + assemblies + environment), then a real launch.
   `note.log` in `%LOCALAPPDATA%\hermes-board-note\` records what the host actually did.

Nothing here is machine-specific: `board-note.ps1` takes `-Base` (default
`http://127.0.0.1:9130`), the `.cmd` uses `%~dp0`, and the installer reads the distro from its
own UNC path.
