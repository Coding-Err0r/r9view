# Drives r9view for end-to-end testing: real mouse clicks and keystrokes sent to
# the real window, then a screenshot of just that window.
#
# Steps are semicolon separated:
#   wait:<seconds>        pause
#   keys:<SendKeys>       keyboard, e.g. keys:{RIGHT}{RIGHT}
#   move:<fx>,<fy>        move the pointer to a fraction of the window
#   click:<fx>,<fy>       single click there
#   dbl:<fx>,<fy>         double click there
#   tap3:<fx>,<fy>        three rapid clicks (tests skip accumulation)
#   shot:<path>           capture the window
param(
  [Parameter(Mandatory = $true)][string]$Target,
  [Parameter(Mandatory = $true)][string]$Steps,
  [int]$StartWait = 7,
  [switch]$KeepOpen
)

$env:Path = "C:\msys64\ucrt64\bin;" + $env:Path
$env:R9VIEW_DEBUG = "1"

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public const uint DOWN = 0x0002, UP = 0x0004;
  public static void Click() {
    mouse_event(DOWN, 0, 0, 0, IntPtr.Zero);
    mouse_event(UP, 0, 0, 0, IntPtr.Zero);
  }
}
'@

# Without this the window rect is in physical pixels while the screen capture
# is virtualised, so the screenshot does not line up with where the clicks go.
[void][Win]::SetProcessDPIAware()

$err = "$env:TEMP\drive-err.txt"
$proc = Start-Process -FilePath "C:\Users\death\Desktop\r9view\build\r9view.exe" `
    -ArgumentList "`"$Target`"" -RedirectStandardError $err `
    -RedirectStandardOutput "$env:TEMP\drive-out.txt" -PassThru
Start-Sleep -Seconds $StartWait
$proc.Refresh()

if ($proc.HasExited) {
  Write-Output "FAILED: app exited with $($proc.ExitCode)"
  Get-Content $err -ErrorAction SilentlyContinue | Select-Object -First 20
  exit 1
}

$h = $proc.MainWindowHandle
[void][Win]::ShowWindow($h, 3)        # maximise, so fractions are stable
Start-Sleep -Milliseconds 800
[void][Win]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 400

function Get-Rect {
  $r = New-Object Win+RECT
  [void][Win]::GetWindowRect($h, [ref]$r)
  return $r
}

function Move-To([double]$fx, [double]$fy) {
  $r = Get-Rect
  $x = [int]($r.L + ($r.R - $r.L) * $fx)
  $y = [int]($r.T + ($r.B - $r.T) * $fy)
  [void][Win]::SetCursorPos($x, $y)
  Start-Sleep -Milliseconds 120
}

function Shot([string]$path) {
  $r = Get-Rect
  $w = $r.R - $r.L; $hh = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $hh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen((New-Object System.Drawing.Point($r.L, $r.T)), [System.Drawing.Point]::Empty, (New-Object System.Drawing.Size($w, $hh)))
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Output "  shot -> $path"
}

foreach ($step in $Steps.Split(';')) {
  $s = $step.Trim()
  if ($s -eq "") { continue }
  $verb, $arg = $s.Split(':', 2)
  Write-Output "step: $s"
  switch ($verb) {
    'wait'  { Start-Sleep -Milliseconds ([double]$arg * 1000) }
    'keys'  { [System.Windows.Forms.SendKeys]::SendWait($arg); Start-Sleep -Milliseconds 350 }
    'move'  { $p = $arg.Split(','); Move-To ([double]$p[0]) ([double]$p[1]) }
    'click' { $p = $arg.Split(','); Move-To ([double]$p[0]) ([double]$p[1]); [Win]::Click() }
    'dbl'   {
      $p = $arg.Split(','); Move-To ([double]$p[0]) ([double]$p[1])
      [Win]::Click(); Start-Sleep -Milliseconds 70; [Win]::Click()
    }
    'tap3'  {
      $p = $arg.Split(','); Move-To ([double]$p[0]) ([double]$p[1])
      [Win]::Click(); Start-Sleep -Milliseconds 70
      [Win]::Click(); Start-Sleep -Milliseconds 70; [Win]::Click()
    }
    'shot'  { Shot $arg }
    default { Write-Output "  ?? unknown step" }
  }
}

Write-Output "--- stderr ---"
Get-Content $err -ErrorAction SilentlyContinue |
  Where-Object { $_ -notmatch 'no frame!|hwaccel|VK_KHR|lacking required|Unsupported hwdec|Failed to initialize VAAPI|Discarding potentially' } |
  Select-Object -First 20

if (-not $KeepOpen -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
