<#
.SYNOPSIS
  Installs r9view on Windows, for the current user, with no administrator rights.

.DESCRIPTION
  Downloads the latest release, unpacks it into %LOCALAPPDATA%\Programs\r9view,
  adds a Start Menu entry, puts r9view on PATH, and registers it under "Open
  with" for the images, comics, video and audio it can read.

  Nothing is written outside the user's own profile and HKEY_CURRENT_USER, and
  everything it does is undone by -Uninstall.

.EXAMPLE
  irm https://raw.githubusercontent.com/Coding-Err0r/r9view/main/install.ps1 | iex

.EXAMPLE
  # from a zip you already have, somewhere of your choosing
  .\install.ps1 -Zip .\r9view-1.0.0-windows-x64.zip -Prefix D:\Apps\r9view

.EXAMPLE
  .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
  [string]$Prefix = "$env:LOCALAPPDATA\Programs\r9view",
  # A local zip to install instead of downloading a release.
  [string]$Zip = "",
  [switch]$NoShortcuts,
  [switch]$NoAssociations,
  [switch]$NoPath,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Repo = "Coding-Err0r/r9view"
$ProgId = "r9view.media"

function Say($m)  { Write-Host "  $m" }
function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }

# Everything r9view will offer to open. Images and comics it decodes itself;
# the rest it hands to mpv.
$Extensions = @(
  # comics and archives
  ".cbz", ".cbr", ".cb7", ".cbt",
  # images
  ".png", ".jpg", ".jpeg", ".jpe", ".jfif", ".webp", ".avif", ".jxl", ".heic",
  ".heif", ".gif", ".bmp", ".tif", ".tiff", ".psd", ".svg", ".ico", ".tga",
  ".jp2", ".exr", ".qoi", ".dds", ".xcf",
  # video
  ".mkv", ".mp4", ".m4v", ".avi", ".mov", ".webm", ".ts", ".m2ts", ".mts",
  ".wmv", ".asf", ".flv", ".mpg", ".mpeg", ".m2v", ".vob", ".ogv", ".rm",
  ".rmvb", ".3gp", ".divx", ".mxf", ".mk3d",
  # audio
  ".mp3", ".flac", ".m4a", ".aac", ".ogg", ".oga", ".opus", ".wav", ".wma",
  ".alac", ".ape", ".mka", ".ac3", ".dts", ".aiff", ".dsf", ".mpc", ".wv"
)

# ---------------------------------------------------------------- uninstall --
if ($Uninstall) {
  Step "Removing r9view"

  $lnk = Join-Path ([Environment]::GetFolderPath("Programs")) "r9view.lnk"
  if (Test-Path $lnk) { Remove-Item $lnk -Force; Say "Start Menu entry" }
  $desk = Join-Path ([Environment]::GetFolderPath("Desktop")) "r9view.lnk"
  if (Test-Path $desk) { Remove-Item $desk -Force; Say "desktop shortcut" }

  Remove-Item -Recurse -Force "HKCU:\Software\Classes\$ProgId" -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force "HKCU:\Software\Classes\Applications\r9view.exe" -ErrorAction SilentlyContinue
  foreach ($e in $Extensions) {
    $k = "HKCU:\Software\Classes\$e\OpenWithProgids"
    if (Test-Path $k) {
      Remove-ItemProperty -Path $k -Name $ProgId -ErrorAction SilentlyContinue
    }
  }
  Say "file associations"

  $bin = Join-Path $Prefix "bin"
  $user = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($user -and ($user -split ';' -contains $bin)) {
    $kept = ($user -split ';' | Where-Object { $_ -ne $bin }) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $kept, "User")
    Say "PATH entry"
  }

  Remove-Item -Recurse -Force "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\r9view" -ErrorAction SilentlyContinue
  Say "Apps and features entry"

  if (Test-Path $Prefix) {
    try {
      Remove-Item -Recurse -Force $Prefix
      Say "$Prefix"
    } catch {
      Warn "could not remove $Prefix -- close r9view and run this again"
    }
  }

  Write-Host ""
  Write-Host "r9view removed. Settings and bookmarks are kept in the registry" -ForegroundColor Green
  Write-Host "under HKCU\Software\r9view; delete that key too if you want them gone."
  return
}

# ------------------------------------------------------------------ install --
if (-not [Environment]::Is64BitOperatingSystem) { throw "r9view needs 64-bit Windows." }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("r9view-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  if ($Zip -ne "") {
    if (-not (Test-Path $Zip)) { throw "no such file: $Zip" }
    $archive = (Resolve-Path $Zip).Path
    Step "Installing from $archive"
  } else {
    Step "Looking up the latest release"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    $asset = $rel.assets | Where-Object { $_.name -like "r9view-*-windows-x64.zip" } | Select-Object -First 1
    if (-not $asset) { throw "that release has no Windows zip in it" }
    Say "$($rel.tag_name) -- $($asset.name), $([math]::Round($asset.size/1MB,1)) MB"

    $archive = Join-Path $tmp $asset.name
    Step "Downloading"
    $pref = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest $asset.browser_download_url -OutFile $archive -UseBasicParsing
    $ProgressPreference = $pref
  }

  Step "Unpacking"
  $unpack = Join-Path $tmp "x"
  Expand-Archive -Path $archive -DestinationPath $unpack -Force
  # The zip holds a single r9view\ folder; tolerate it being flat as well.
  $root = Join-Path $unpack "r9view"
  if (-not (Test-Path (Join-Path $root "r9view.exe"))) { $root = $unpack }
  if (-not (Test-Path (Join-Path $root "r9view.exe"))) { throw "no r9view.exe inside the zip" }

  # Replacing a running copy fails in a confusing way, so say so plainly.
  $running = Get-Process r9view -ErrorAction SilentlyContinue
  if ($running) { throw "r9view is running. Close it and try again." }

  Step "Installing to $Prefix"
  $bin = Join-Path $Prefix "bin"
  if (Test-Path $bin) { Remove-Item -Recurse -Force $bin }
  New-Item -ItemType Directory -Force -Path $bin | Out-Null
  Copy-Item "$root\*" $bin -Recurse -Force
  $exe = Join-Path $bin "r9view.exe"

  # ---- Start Menu ----------------------------------------------------------
  if (-not $NoShortcuts) {
    Step "Start Menu"
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Programs")) "r9view.lnk"))
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = $bin
    $lnk.Description = "Touch-first image, comic and video viewer"
    $lnk.Save()
    Say "r9view"
  }

  # ---- PATH ----------------------------------------------------------------
  if (-not $NoPath) {
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $user) { $user = "" }
    if ($user -split ';' -notcontains $bin) {
      Step "Adding to PATH"
      [Environment]::SetEnvironmentVariable("Path", ($user.TrimEnd(';') + ";" + $bin).TrimStart(';'), "User")
      Say "open a new terminal for this to take effect"
    }
  }

  # ---- Open with -----------------------------------------------------------
  # r9view is added to the "Open with" list for what it can read, and is not
  # made the default for anything. Taking over every video on the machine
  # without being asked is not a thing an installer should do.
  if (-not $NoAssociations) {
    Step "Registering under Open with"
    New-Item -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Classes\$ProgId" -Name "(default)" -Value "Media file"
    Set-ItemProperty -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Name "(default)" -Value "`"$exe`" `"%1`""
    New-Item -Path "HKCU:\Software\Classes\$ProgId\DefaultIcon" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Classes\$ProgId\DefaultIcon" -Name "(default)" -Value "`"$exe`",0"

    New-Item -Path "HKCU:\Software\Classes\Applications\r9view.exe\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Classes\Applications\r9view.exe\shell\open\command" -Name "(default)" -Value "`"$exe`" `"%1`""
    Set-ItemProperty -Path "HKCU:\Software\Classes\Applications\r9view.exe" -Name "FriendlyAppName" -Value "r9view"
    New-Item -Path "HKCU:\Software\Classes\Applications\r9view.exe\SupportedTypes" -Force | Out-Null

    foreach ($e in $Extensions) {
      New-Item -Path "HKCU:\Software\Classes\$e\OpenWithProgids" -Force | Out-Null
      Set-ItemProperty -Path "HKCU:\Software\Classes\$e\OpenWithProgids" -Name $ProgId -Value ([byte[]]@()) -Type None
      Set-ItemProperty -Path "HKCU:\Software\Classes\Applications\r9view.exe\SupportedTypes" -Name $e -Value ""
    }
    Say "$($Extensions.Count) file types"
  }

  # ---- uninstaller ---------------------------------------------------------
  Copy-Item $PSCommandPath (Join-Path $Prefix "install.ps1") -Force -ErrorAction SilentlyContinue
  $unins = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\r9view"
  New-Item -Path $unins -Force | Out-Null
  Set-ItemProperty -Path $unins -Name "DisplayName" -Value "r9view"
  Set-ItemProperty -Path $unins -Name "DisplayIcon" -Value $exe
  Set-ItemProperty -Path $unins -Name "InstallLocation" -Value $Prefix
  Set-ItemProperty -Path $unins -Name "Publisher" -Value "Rhineul Islam"
  Set-ItemProperty -Path $unins -Name "NoModify" -Value 1 -Type DWord
  Set-ItemProperty -Path $unins -Name "UninstallString" `
      -Value "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Prefix\install.ps1`" -Uninstall -Prefix `"$Prefix`""

  Write-Host ""
  Write-Host "r9view is installed." -ForegroundColor Green
  Write-Host ""
  Write-Host "  r9view `"D:\Anime\Some Show`"     a season folder, subtitles and all"
  Write-Host "  r9view chapter-01.cbz           a comic"
  Write-Host "  r9view episode.mkv              one file, arrow keys walk the folder"
  Write-Host ""
  Write-Host "  Uninstall from Settings > Apps, or:"
  Write-Host "  powershell -File `"$Prefix\install.ps1`" -Uninstall"
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
