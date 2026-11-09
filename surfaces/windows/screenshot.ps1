param([string]$Out = "")   # default: %TEMP%\board-note-shot.png (never a hardcoded user path)
if (-not $Out) { $Out = Join-Path $env:TEMP "board-note-shot.png" }
# DPI-aware capture: without SetProcessDPIAware this grabs only the virtualised top-left
# region of a scaled display (1280x720 of a 1920x1080 panel) and the note looks off-screen.
Add-Type -Namespace Win32Shot -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][Win32Shot.Dpi]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "shot: $Out ($($b.Width)x$($b.Height))"
