param(
  [string]$Base = "http://127.0.0.1:9130",   # the live board viewer in WSL
  [switch]$ValidateOnly,                      # preflight: stage + environment + exit, no window
  [int]$SelfTest = 0,                         # bounded run: navigate, report, close itself
  [switch]$Topmost,                           # start always-on-top (default: behind windows)
  [switch]$Reset,                             # ignore saved position/size
  [string]$Start = ""                         # "note" | "wide"; empty = reopen where you left it
)
<#
  Board note - a sticky-note window on the Windows desktop showing the Hermes Kanban board.

  Windows-side only by necessity: transparency/always-on-top are exactly what WSLg breaks,
  so this runs natively and reaches the WSL viewer over loopback (WSL2 forwards it).

  It renders nothing itself - the WSL viewer owns both layouts (/note narrow, / wide). This
  is a dumb always-on-top-able frame around them, which is why the note can never disagree
  with the board page about content.

  Hard-won details (each one cost a debugging cycle):
   1. WebView2 assemblies CANNOT be loaded from a UNC path (0x80131515) -> stage to %LOCALAPPDATA%.
   2. EnsureCoreWebView2Async($null) derives its profile next to powershell.exe (System32) and
      kills the process silently, exit 2, no exception, nothing in the event log -> build an
      explicit CoreWebView2Environment with a folder we own, BEFORE any UI exists.
   3. The WPF WebView2 control dies the same way; the WinForms control works.
   4. The initial window must be ON SCREEN: an off-screen (-10000) window stalls init forever.
#>

$ErrorActionPreference = "Stop"

# 0. Single instance. The logon shortcut, a double-clicked .cmd and a re-launch after an
#    update all run this script; two windows would each claim their own saved position.
$running = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object {
  $_.Id -ne $PID -and $_.MainWindowTitle -eq "Board"
}
if ($running -and -not ($ValidateOnly -or $SelfTest)) {
  Write-Output "already running (pid $($running[0].Id)) - not starting a second note"
  exit 0
}

# 5. DPI awareness. This display is scaled, and a DPI-unaware process is bitmap-stretched by
#    Windows: the whole note renders blurry AND reports a virtualised screen size (1280x720
#    for a 1920x1080 panel), so placement maths and any screenshot are in the wrong space.
#    Opt in before ANY window exists.
if (-not ("Win32Dpi" -as [type])) {
  Add-Type -Namespace Win32Dpi -Name Aware -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
}
[void][Win32Dpi.Aware]::SetProcessDPIAware()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stage = Join-Path $env:LOCALAPPDATA "hermes-board-note"
$stageDll = Join-Path $stage "webview2"
$statePath = Join-Path $stage "state.json"

function Fail($msg) { Write-Output "ERROR: $msg"; exit 1 }

# ---------------------------------------------------------------- staging ----
New-Item -ItemType Directory -Force -Path $stageDll | Out-Null
foreach ($dll in @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "WebView2Loader.dll")) {
  $src = Join-Path (Join-Path $here "webview2") $dll
  if (-not (Test-Path $src)) { Fail "missing dependency: $src" }
  $dst = Join-Path $stageDll $dll
  $need = -not (Test-Path $dst)
  if (-not $need) { $need = (Get-Item $src).Length -ne (Get-Item $dst).Length }
  if ($need) { Copy-Item -Path $src -Destination $dst -Force }
}
$env:PATH = "$stageDll;$env:PATH"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Path (Join-Path $stageDll "Microsoft.Web.WebView2.Core.dll")
Add-Type -Path (Join-Path $stageDll "Microsoft.Web.WebView2.WinForms.dll")

# ------------------------------------------------------------- environment ----
# See note 2 in the header: never let the control pick its own user-data folder.
$udf = Join-Path $stage "profile"
$coreEnv = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $udf, $null).GetAwaiter().GetResult()
if (-not $coreEnv) { Fail "could not create the WebView2 environment" }
if ($ValidateOnly) { Write-Output "ok: staged, assemblies load, environment ready ($udf)"; exit 0 }

# --------------------------------------------------------------- win32 glue ----
if (-not ("Win32Native" -as [type])) {
  Add-Type -Namespace Win32Native -Name User32 -MemberDefinition @"
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
"@
}

# -------------------------------------------------------------- persisted ui ----
$ui = @{ left = $null; top = $null; width = 430; height = 560; mode = "note"; topmost = $false }
if ((-not $Reset) -and (Test-Path $statePath)) {
  try {
    $saved = Get-Content $statePath -Raw | ConvertFrom-Json
    foreach ($k in @("left", "top", "width", "height", "mode", "topmost")) {
      if ($null -ne $saved.$k) { $ui[$k] = $saved.$k }
    }
  } catch { }
}
if ($Topmost) { $ui.topmost = $true }

function Save-Ui {
  # Written next to the staged copy, not into WSL: a note that cannot persist its own
  # position is a note the user has to re-place every login.
  try { ($ui | ConvertTo-Json) | Set-Content -Path $statePath -Encoding UTF8 } catch { }
}

$sizes = @{
  note = @{ width = $ui.width; height = $ui.height }
  wide = @{ width = 1180; height = 820 }
}
if ($ui.mode -eq "wide") { $sizes.wide.width = [Math]::Max(900, $ui.width); $sizes.wide.height = [Math]::Max(600, $ui.height) }

# ------------------------------------------------------------------- window ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Board"
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.ShowInTaskbar = $true
$form.Width = [int]$sizes[$ui.mode].width
$form.Height = [int]$sizes[$ui.mode].height
$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($null -eq $ui.left) { $ui.left = $area.Right - $form.Width - 40; $ui.top = $area.Top + 80 }
$form.Left = [int]$ui.left
$form.Top = [int]$ui.top
$form.Topmost = [bool]$ui.topmost

# Native strip: the window's own chrome. It owns drag, the menu, the mode toggle and close,
# because the WebView2 child HWND swallows every mouse event over the page itself.
$strip = New-Object System.Windows.Forms.Panel
$strip.Dock = 'Top'
$strip.Height = 26
$strip.BackColor = [System.Drawing.Color]::FromArgb(43, 49, 56)
$form.Controls.Add($strip)

# Absolute positions + anchors, NOT Dock: with three docked children the fill label is
# laid out before the right-docked buttons and the counts text clips to its tail.
$title = New-Object System.Windows.Forms.Label
$title.Text = "BOARD"
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(8, 6)
$strip.Controls.Add($title)

$counts = New-Object System.Windows.Forms.Label
$counts.Text = "connecting"   # replaced by the page's live counts
$counts.ForeColor = [System.Drawing.Color]::FromArgb(200, 205, 210)
$counts.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$counts.AutoSize = $false
$counts.TextAlign = 'MiddleLeft'
$counts.Location = New-Object System.Drawing.Point(70, 4)
$counts.Size = New-Object System.Drawing.Size(300, 18)
$counts.Anchor = 'Top,Left,Right'
$strip.Controls.Add($counts)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "X"
$btnClose.Size = New-Object System.Drawing.Size(28, 20)
$btnClose.Location = New-Object System.Drawing.Point(398, 3)
$btnClose.Anchor = 'Top,Right'
$btnClose.FlatStyle = 'Flat'
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(43, 49, 56)
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.TabStop = $false
$strip.Controls.Add($btnClose)

$btnMode = New-Object System.Windows.Forms.Button
$btnMode.Text = "full"
$btnMode.Size = New-Object System.Drawing.Size(46, 20)
$btnMode.Location = New-Object System.Drawing.Point(350, 3)
$btnMode.Anchor = 'Top,Right'
$btnMode.FlatStyle = 'Flat'
$btnMode.ForeColor = [System.Drawing.Color]::White
$btnMode.BackColor = [System.Drawing.Color]::FromArgb(43, 49, 56)
$btnMode.FlatAppearance.BorderSize = 0
$btnMode.TabStop = $false
$strip.Controls.Add($btnMode)

$strip.Add_Resize({
  # keep the right-hand buttons pinned when the note is resized
  $btnClose.Left = $strip.Width - $btnClose.Width - 4
  $btnMode.Left = $btnClose.Left - $btnMode.Width - 2
  $counts.Width = [Math]::Max(60, $btnMode.Left - $counts.Left - 6)
})

$web = New-Object Microsoft.Web.WebView2.WinForms.WebView2
$web.Dock = 'Fill'
$form.Controls.Add($web)
$web.BringToFront()

# A log is not optional here: every failure mode in this file (WebView2 init, navigation,
# mode switches) happens inside a WinForms callback where an exception is invisible.
$logPath = Join-Path $stage "note.log"
function Log($m) { try { Add-Content -Path $logPath -Value ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss.fff), $m) -Encoding UTF8 } catch { } }
Set-Content -Path $logPath -Value ("--- start {0} (Start={1})" -f (Get-Date -Format s), $Start) -Encoding UTF8

$script:ready = $false
$script:retry = $null
$startMode = if ($Start -in @("note", "wide")) { $Start } else { $ui.mode }
$script:mode = $startMode
$script:lastUrl = if ($startMode -eq "wide") { "$Base/?from=note" } else { "$Base/note" }
Log "init: mode=$($script:mode) start=$Start url=$($script:lastUrl)"

function Apply-Mode($mode) {
  Log "apply-mode -> $mode (from $($script:mode))"
  # Each mode remembers its own geometry, so toggling back restores the note's place.
  if ($mode -ne $script:mode) {
    if ($script:mode -eq "wide") { $ui.width = $form.Width; $ui.height = $form.Height }
    $script:mode = $mode
    $ui.mode = $mode
  }
  $script:suppress = $true
  if ($mode -eq "wide") {
    $form.Width = [int]$sizes.wide.width
    $form.Height = [int]$sizes.wide.height
    $btnMode.Text = "note"
  } else {
    $form.Width = [int]$ui.width
    $form.Height = [int]$ui.height
    $btnMode.Text = "full"
  }
  $onScreen = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
  if ($form.Left + $form.Width -gt $onScreen.Right) { $form.Left = $onScreen.Right - $form.Width }
  if ($form.Left -lt $onScreen.Left) { $form.Left = $onScreen.Left }
  if ($form.Top + $form.Height -gt $onScreen.Bottom) { $form.Top = [Math]::Max($onScreen.Top, $onScreen.Bottom - $form.Height) }
  if ($form.Top -lt $onScreen.Top) { $form.Top = $onScreen.Top }
  $script:suppress = $false
  Save-Ui
}

function Go-To($url) {
  $script:lastUrl = $url
  try { $web.CoreWebView2.Navigate($url) } catch { }
}

function Start-Retry {
  if ($script:retry) { return }
  $script:retry = New-Object System.Windows.Forms.Timer
  $script:retry.Interval = 15000
  $script:retry.Add_Tick({ if ($script:ready) { $script:retry.Stop(); $script:retry = $null; Go-To $script:lastUrl } })
  $script:retry.Start()
}

function OfflinePage($reason) {
  $h = @"
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
 body{margin:0;height:100%;background:#fffdf3;color:#22262b;font:12px "Segoe UI",sans-serif;padding:10px}
 .b{background:#7f1d1d;color:#fff;padding:6px 8px;border-radius:4px;margin-bottom:8px;font-weight:600}
 code{background:#f0ede2;padding:1px 4px;border-radius:3px}
</style></head><body>
<div class="b">Board viewer unreachable</div>
<p>$reason</p>
<p>The note cannot see <code>$Base</code>. It will retry every 15 seconds and refresh itself
as soon as the viewer answers.</p>
<p>Start it with:<br><code>systemctl --user start hermes-board.service</code></p>
</body></html>
"@
  $web.CoreWebView2.NavigateToString($h)
}

function Show-Refresh {
  if ($script:mode -eq "wide") { Go-To "$Base/?from=note" } else { Go-To "$Base/note" }
}

# ------------------------------------------------------------------- menu -----
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miTop = $menu.Items.Add("Always on top")
$miTop.CheckOnClick = $true
$miTop.Checked = [bool]$ui.topmost
$miTop.add_Click({ $form.Topmost = $miTop.Checked; $ui.topmost = $miTop.Checked; Save-Ui })
$miMode = $menu.Items.Add("Full board / note")
$miMode.add_Click({ $target = if ($script:mode -eq "wide") { "note" } else { "wide" }; Apply-Mode $target; Show-Refresh })
$miRefresh = $menu.Items.Add("Refresh")
$miRefresh.add_Click({ Show-Refresh })
$miNote = $menu.Items.Add("Compact note")
$miNote.add_Click({ Apply-Mode "note"; Go-To "$Base/note" })
$miWide = $menu.Items.Add("Open full board")
$miWide.add_Click({ Apply-Mode "wide"; Go-To "$Base/?from=note" })
$miBrowser = $menu.Items.Add("Open in browser")
$miBrowser.add_Click({ Start-Process "$Base/note" })
$miResetPos = $menu.Items.Add("Reset position")
$miResetPos.add_Click({ $form.Left = $area.Right - $form.Width - 40; $form.Top = $area.Top + 80; Save-Ui })
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miClose = $menu.Items.Add("Close note")
$miClose.add_Click({ $form.Close() })

$btnClose.add_Click({ $form.Close() })
$btnMode.add_Click({
  $target = if ($script:mode -eq "wide") { "note" } else { "wide" }
  $url = if ($target -eq "wide") { "$Base/?from=note" } else { "$Base/note" }
  Apply-Mode $target
  Go-To $url
})

# Drag anywhere on the strip, and on the page's own header (via a host message).
$strip.Add_MouseDown({
  param($s, $e)
  if ($e.Button -eq 'Left') { [void][Win32Native.User32]::ReleaseCapture(); [void][Win32Native.User32]::SendMessage($form.Handle, 0xA1, 0x2, 0) }
  elseif ($e.Button -eq 'Right') { $menu.Show([System.Windows.Forms.Cursor]::Position) }
})
$title.Add_MouseDown({
  param($s, $e)
  if ($e.Button -eq 'Left') { [void][Win32Native.User32]::ReleaseCapture(); [void][Win32Native.User32]::SendMessage($form.Handle, 0xA1, 0x2, 0) }
  elseif ($e.Button -eq 'Right') { $menu.Show([System.Windows.Forms.Cursor]::Position) }
})
$counts.Add_MouseDown({
  param($s, $e)
  if ($e.Button -eq 'Left') { [void][Win32Native.User32]::ReleaseCapture(); [void][Win32Native.User32]::SendMessage($form.Handle, 0xA1, 0x2, 0) }
  elseif ($e.Button -eq 'Right') { $menu.Show([System.Windows.Forms.Cursor]::Position) }
})

$form.Add_Move({ if (-not $script:suppress) { $ui.left = $form.Left; $ui.top = $form.Top; Save-Ui } })
$form.Add_Resize({
  if (-not $script:suppress) {
    if ($script:mode -eq "wide") { $sizes.wide.width = $form.Width; $sizes.wide.height = $form.Height }
    else { $ui.width = $form.Width; $ui.height = $form.Height }
    Save-Ui
  }
})

# ------------------------------------------------------------- host messages ----
$web.add_WebMessageReceived({
  param($s, $e)
  try { $msg = $e.WebMessageAsJson | ConvertFrom-Json } catch { return }
  switch ($msg.hermes) {
    "drag"  { [void][Win32Native.User32]::ReleaseCapture(); [void][Win32Native.User32]::SendMessage($form.Handle, 0xA1, 0x2, 0) }
    "menu"  { $menu.Show([System.Windows.Forms.Cursor]::Position) }
    "counts" { if ($msg.text) { $counts.Text = $msg.text } }
    "mode"  { Apply-Mode $msg.mode }
  }
})

$web.add_NavigationStarting({
  param($s, $e)
  # CoreWebView2NavigationCompletedEventArgs has NO Uri property (only NavigationStarting
  # does), so the target is captured here for the completed handler to read.
  $script:navUri = $e.Uri
  # Anything that is not our viewer opens in the real browser instead of hijacking the note.
  if ($e.Uri -notlike "$Base*") { $e.Cancel = $true; Start-Process $e.Uri }
})

$web.add_NavigationCompleted({
  param($s, $e)
  if (-not $e.IsSuccess) {
    Log "nav FAILED: $($script:navUri) $($e.WebErrorStatus)"
    $script:ready = $false
    if ($script:booted) { $counts.Text = "viewer offline - retrying" }
    $script:booted = $true
    OfflinePage ("Could not load $($script:navUri) ($($e.WebErrorStatus)).")
    Start-Retry
    return
  }
  if ($script:retry) { $script:retry.Stop(); $script:retry = $null }
  $script:ready = $true
  $script:booted = $true
  $uri = if ($script:navUri) { $script:navUri } else { [string]$web.Source }
  $path = try { ([Uri]$uri).AbsolutePath } catch { "" }
  Log "nav ok: $uri path=$path"
  if ($path -eq "/note") { Apply-Mode "note" }
  elseif ($path -eq "/" -or $path -eq "") { Apply-Mode "wide" }
})

# ------------------------------------------------------------------- start -----
$script:booted = $false
$form.Add_Shown({
  $script:suppress = $true
  $script:initTask = $web.EnsureCoreWebView2Async($coreEnv)
})
$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = 1000
$script:ticks = 0
$poll.Add_Tick({
  $t = $script:initTask
  if ($null -eq $t) { return }
  if (-not $t.IsCompleted) { $script:ticks++; if ($script:ticks -gt 30) { $poll.Stop(); OfflinePage "WebView2 did not initialise within 30 s."; Start-Retry }; return }
  $poll.Stop()
  if ($t.IsFaulted) { OfflinePage ("WebView2 failed to start: " + $t.Exception.GetBaseException().Message); Start-Retry; return }
  $web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $false
  $web.CoreWebView2.Settings.IsStatusBarEnabled = $false
  $web.CoreWebView2.Settings.AreDevToolsEnabled = $false
  $web.CoreWebView2.Settings.IsZoomControlEnabled = $false
  $script:suppress = $false
  Go-To $script:lastUrl
})
$poll.Start()

if ($SelfTest -gt 0) {
  $st = New-Object System.Windows.Forms.Timer
  $st.Interval = $SelfTest * 1000
  $st.Add_Tick({
    $st.Stop()
    Write-Output ("SELFTEST: mode=$($script:mode) ready=$($script:ready) url=$($web.Source) size=$($form.Width)x$($form.Height)")
    $form.Close()
  })
  $st.Start()
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
Write-Output ("CLOSED: mode=$($script:mode) width=$($ui.width) height=$($ui.height) topmost=$($ui.topmost) state=$statePath")
