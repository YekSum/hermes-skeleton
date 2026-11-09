param([string]$Url = "http://127.0.0.1:9130/healthz", [int]$Seconds = 30, [int]$Left = 100, [int]$Top = 100)
# WinForms-hosted WebView2 self-test, with progress polling so a stalled init is
# distinguishable from a crashed one.
$ErrorActionPreference = "Stop"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$log   = Join-Path $env:TEMP "wv2-selftest.log"
function Say($m) { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss.fff), $m) -Encoding UTF8 }
Set-Content -Path $log -Value ("--- winforms run {0}" -f (Get-Date -Format s)) -Encoding UTF8

$stage    = Join-Path $env:LOCALAPPDATA "hermes-board-note"
$stageDll = Join-Path $stage "webview2"
New-Item -ItemType Directory -Force -Path $stageDll | Out-Null
foreach ($dll in @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "WebView2Loader.dll")) {
  Copy-Item -Path (Join-Path (Join-Path $here "webview2") $dll) -Destination (Join-Path $stageDll $dll) -Force
}
$env:PATH = "$stageDll;$env:PATH"

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Path (Join-Path $stageDll "Microsoft.Web.WebView2.Core.dll")
Add-Type -Path (Join-Path $stageDll "Microsoft.Web.WebView2.WinForms.dll")

$udf = Join-Path $stage "profile"
$coreEnv = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $udf, $null).GetAwaiter().GetResult()
Say "environment ready"

$script:result = "no-result"
$form = New-Object System.Windows.Forms.Form
$form.Text = "wv2-selftest"
$form.Width = 800; $form.Height = 500
$form.StartPosition = 'Manual'; $form.Left = $Left; $form.Top = $Top
$web = New-Object Microsoft.Web.WebView2.WinForms.WebView2
$web.Dock = 'Fill'
$form.Controls.Add($web)

$web.add_NavigationCompleted({
  param($s, $e)
  $script:result = "NAV ok=$($e.IsSuccess) err=$($e.WebErrorStatus)"
  Say $script:result
  $form.BeginInvoke([action]{ $form.Close() }) | Out-Null
})
$script:initTask = $null
$form.Add_Shown({
  Say "shown; EnsureCoreWebView2Async"
  $script:initTask = $web.EnsureCoreWebView2Async($coreEnv)
  Say ("task type: " + $script:initTask.GetType().Name)
})
# poll the init task from the UI thread so we can see Pending vs Faulted vs RanToCompletion
$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = 2000
$script:ticks = 0
$poll.Add_Tick({
  $script:ticks++
  $t = $script:initTask
  if ($null -eq $t) { Say "poll: no task yet"; return }
  Say ("poll {0}: status={1}" -f $script:ticks, $t.Status)
  if ($t.IsCompleted) {
    $poll.Stop()
    if ($t.IsFaulted) {
      $inner = $t.Exception.GetBaseException()
      $script:result = "INIT-FAILED: $($inner.GetType().Name): $($inner.Message)"
      Say $script:result; $form.Close()
    } else {
      Say "core ready; navigating"
      try { $web.CoreWebView2.Navigate($Url) } catch { Say ("NAV threw: " + $_.Exception.Message); $form.Close() }
    }
  }
})
$poll.Start()
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $Seconds * 1000
$timer.Add_Tick({ $script:result = "TIMEOUT after $Seconds s (task status: $($script:initTask.Status))"; Say $script:result; $form.Close() })
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
Say "run loop ended"
Write-Output "RESULT: $($script:result)"
