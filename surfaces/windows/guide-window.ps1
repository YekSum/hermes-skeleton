<#
    guide-window.ps1 — the Windows half of the chat-head window.

    A small always-on-top bubble that opens the onboarding guide in a window. It talks to
    guide-bridge.py in WSL (http://127.0.0.1:8765) and knows nothing about Hermes, sessions, or paths.

    Behaviour, deliberately Messenger-shaped:
      click the bubble      -> the panel opens
      drag the bubble       -> it moves (a drag is not a click)
      X on the panel        -> collapses back to the bubble, NOT quit
      right-click the head  -> Quit

    Run:   powershell -ExecutionPolicy Bypass -File guide-window.ps1
    Stop:  right-click the bubble -> Quit
    Env:   GUIDE_BRIDGE  (default http://127.0.0.1:8765)
#>

param(
    [string]$Bridge = $(if ($env:GUIDE_BRIDGE) { $env:GUIDE_BRIDGE } else { "http://127.0.0.1:8765" }),
    [switch]$ValidateOnly   # parse the XAML and exit — used by the repo's checks, no window appears
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="72" Height="72" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        ResizeMode="NoResize" WindowStartupLocation="Manual" Title="guide">
  <Grid>
    <!-- the head -->
    <Grid x:Name="Head" Width="72" Height="72" Cursor="Hand">
      <Ellipse Fill="#1F6FEB" Stroke="#0B3D91" StrokeThickness="2"/>
      <TextBlock Text="g" FontSize="34" FontWeight="Bold" Foreground="White"
                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Grid>

    <!-- the panel -->
    <Border x:Name="Panel" Visibility="Collapsed" Width="380" Height="540"
            Background="#0D1117" BorderBrush="#30363D" BorderThickness="1" CornerRadius="10">
      <Grid Margin="10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="2,0,2,8">
          <TextBlock Text="guide" Foreground="#C9D1D9" FontSize="13" FontWeight="SemiBold"/>
          <Button x:Name="Minimize" Content="—" HorizontalAlignment="Right" Width="26" Height="22"
                  Background="Transparent" Foreground="#8B949E" BorderThickness="0" ToolTip="collapse"/>
        </Grid>

        <ScrollViewer x:Name="Scroller" Grid.Row="1" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="Transcript"/>
        </ScrollViewer>

        <TextBox x:Name="Input" Grid.Row="2" Margin="0,8,0,6" Height="56"
                 AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                 Background="#161B22" Foreground="#C9D1D9" BorderBrush="#30363D"
                 Padding="8" FontSize="13"/>

        <Grid Grid.Row="3">
          <TextBlock x:Name="Status" Foreground="#8B949E" FontSize="11" VerticalAlignment="Center"/>
          <Button x:Name="Send" Content="Send" HorizontalAlignment="Right" Width="64" Height="26"
                  Background="#238636" Foreground="White" BorderThickness="0"/>
        </Grid>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

if ($ValidateOnly) {
    $null = [Windows.Markup.XamlReader]::Parse($xaml)
    Write-Output "xaml ok"
    exit 0
}

$win = [Windows.Markup.XamlReader]::Parse($xaml)
$head      = $win.FindName("Head")
$panel     = $win.FindName("Panel")
$transcript= $win.FindName("Transcript")
$scroller  = $win.FindName("Scroller")
$input     = $win.FindName("Input")
$send      = $win.FindName("Send")
$status    = $win.FindName("Status")
$minimize  = $win.FindName("Minimize")

# ── state ────────────────────────────────────────────────────────────────────
$script:expanded = $false
$script:downPoint = $null
$script:dragged = $false
$script:pressed = $false

function Set-Expanded([bool]$on) {
    $script:expanded = $on
    if ($on) {
        $win.Width = 380; $win.Height = 540
        # keep the panel on screen: anchor to the right edge of the head
        $screen = [System.Windows.SystemParameters]::WorkArea
        if ($win.Left + 380 -gt $screen.Right) { $win.Left = $screen.Right - 390 }
        if ($win.Top + 540 -gt $screen.Bottom) { $win.Top = $screen.Bottom - 550 }
        $head.Visibility = "Collapsed"; $panel.Visibility = "Visible"
        $input.Focus() | Out-Null
    } else {
        $win.Width = 72; $win.Height = 72
        $panel.Visibility = "Collapsed"; $head.Visibility = "Visible"
    }
}

function Add-Message([string]$who, [string]$text) {
    $colour = if ($who -eq "you") { "#58A6FF" } else { "#C9D1D9" }
    $label  = if ($who -eq "you") { "you" } else { "guide" }
    $border = New-Object System.Windows.Controls.Border
    $border.Margin = "2,0,2,8"
    $border.Padding = "8,6"
    $border.CornerRadius = "6"
    $border.Background = if ($who -eq "you") { "#161B22" } else { "#111820" }
    $sp = New-Object System.Windows.Controls.StackPanel
    $l = New-Object System.Windows.Controls.TextBlock
    $l.Text = $label; $l.FontSize = 10; $l.Foreground = "#8B949E"; $l.Margin = "0,0,0,3"
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text; $t.TextWrapping = "Wrap"; $t.Foreground = $colour; $t.FontSize = 13
    $sp.Children.Add($l) | Out-Null
    $sp.Children.Add($t) | Out-Null
    $border.Child = $sp
    $transcript.Children.Add($border) | Out-Null
    $scroller.ScrollToEnd()
}

# ── async chat: a runspace keeps the UI thread free while the guide thinks ───
$script:pending = $null
$script:pendingPs = $null
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)

$timer.Add_Tick({
    if (-not $script:pending -or -not $script:pending.IsCompleted) { return }
    $timer.Stop()
    try {
        $out = $script:pendingPs.EndInvoke($script:pending)
        $reply = ($out | Where-Object { $_ } | Select-Object -Last 1)
    } catch {
        $reply = "bridge error: $($_.Exception.Message)"
    }
    $script:pendingPs.Dispose()
    $script:pending = $null; $script:pendingPs = $null
    $status.Text = ""
    if (-not $reply) { $reply = "(no answer — is guide-bridge.py running in WSL?)" }
    Add-Message "guide" ([string]$reply)
})

function Send-Text {
    $text = $input.Text.Trim()
    if (-not $text -or $script:pending) { return }
    Add-Message "you" $text
    $input.Clear()
    $status.Text = "thinking…"

    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $null = $ps.AddScript({
        param($baseUrl, $message)
        $body = @{ text = $message } | ConvertTo-Json -Compress
        try {
            $r = Invoke-RestMethod -Uri "$baseUrl/chat" -Method Post -Body $body `
                 -ContentType 'application/json' -TimeoutSec 300
            return $r.reply
        } catch {
            return "bridge error: $($_.Exception.Message) — is guide-bridge.py running in WSL?"
        }
    }).AddArgument($Bridge).AddArgument($text)
    $script:pendingPs = $ps
    $script:pending = $ps.BeginInvoke()
    $timer.Start()
}

# ── window behaviour ────────────────────────────────────────────────────────
# A click and a drag start identically. The old version called DragMove on button-down, which blocks
# until the button is released and then marked the gesture as a drag — so every click on the bubble was
# swallowed and the panel never opened. Drag is now decided in MouseMove, once the pointer has actually
# travelled, and a press that never moves is a click.
$win.Add_MouseLeftButtonDown({
    $script:pressed = $true
    $script:dragged = $false
    $script:downPoint = $_.GetPosition($win)
})

$win.Add_MouseMove({
    if (-not $script:pressed -or $script:dragged) { return }
    $p = $_.GetPosition($win)
    if ([math]::Abs($p.X - $script:downPoint.X) -gt 4 -or
        [math]::Abs($p.Y - $script:downPoint.Y) -gt 4) {
        $script:dragged = $true
        try { $win.DragMove() } catch { }     # never let a drag error swallow the window
    }
})

$win.Add_MouseLeftButtonUp({
    $script:pressed = $false
    if ($script:dragged) { return }           # a drag is not a click
    if (-not $script:expanded) { Set-Expanded $true }
})

$minimize.Add_Click({ Set-Expanded $false })
$send.Add_Click({ Send-Text })
$input.Add_KeyDown({
    if ($_.Key -eq "Enter" -and -not $_.KeyboardDevice.Modifiers.HasFlag("Shift")) {
        $_.Handled = $true; Send-Text
    }
})

# Right-click menu. "Open" exists so the panel is always reachable even if a mouse gesture misbehaves on
# some trackpad configuration - a chat head you cannot open is worse than an ugly menu.
$menu = New-Object System.Windows.Controls.ContextMenu
$open = New-Object System.Windows.Controls.MenuItem
$open.Header = "Open guide"
$open.Add_Click({ Set-Expanded $true })
$quit = New-Object System.Windows.Controls.MenuItem
$quit.Header = "Quit"
$quit.Add_Click({ $win.Close() })
$menu.Items.Add($open) | Out-Null
$menu.Items.Add($quit) | Out-Null
$win.ContextMenu = $menu

# double-click is the second way in
$head.Add_MouseDoubleClick({ Set-Expanded $true })

# start near the bottom-right, above the tray
$screen = [System.Windows.SystemParameters]::WorkArea
$win.Left = $screen.Right - 120
$win.Top  = $screen.Bottom - 200

Add-Message "guide" "Hi — I'm the setup guide. Ask me anything, or say hi to start."
$null = $win.ShowDialog()
