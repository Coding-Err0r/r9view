# Builds a self-contained Windows folder for r9view and zips it.
#
# Run it from anywhere; it drives the MSYS2 UCRT64 toolchain directly rather
# than needing an MSYS2 shell:
#
#   powershell -ExecutionPolicy Bypass -File tools\package-windows.ps1
#
# The result is dist\r9view\ (runnable in place) and dist\r9view-<version>-windows-x64.zip.
param(
  [string]$Ucrt64  = "C:\msys64\ucrt64",
  [string]$Source  = (Split-Path -Parent $PSScriptRoot),
  [string]$Out     = $null,
  # A libmpv-2.dll to ship. Left empty, the pinned build below is downloaded.
  # MSYS2's own libmpv is deliberately NOT used for packaging: it is a 3 MB
  # stub in front of 130-odd ffmpeg, libplacebo and vulkan DLLs, where this one
  # has all of that linked in and depends on nothing but Windows itself.
  [string]$MpvDll  = "",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$MpvRelease = "2026-09-21-e76a35ec95"
$MpvAsset   = "mpv-dev-x86_64-20260921-git-e76a35ec95.7z"
$MpvSha256  = "4f6fe10ee5e7b8cdeb3a749f826e9b4a4b578119944b4f214a17a3692f82797f"

if (-not $Out) { $Out = Join-Path $Source "dist" }
$stage = Join-Path $Out "r9view"
$build = Join-Path $Source "build"
$env:Path = "$Ucrt64\bin;" + $env:Path

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }

if (-not (Test-Path "$Ucrt64\bin\windeployqt.exe")) {
  throw "No Qt found at $Ucrt64. Install it with: pacman -S mingw-w64-ucrt-x86_64-qt6-base mingw-w64-ucrt-x86_64-qt6-declarative mingw-w64-ucrt-x86_64-qt6-svg mingw-w64-ucrt-x86_64-qt6-imageformats mingw-w64-ucrt-x86_64-qt6-tools"
}

# ---- build -----------------------------------------------------------------
if (-not $SkipBuild) {
  Step "Building"
  & cmake -S $Source -B $build -G Ninja -DCMAKE_BUILD_TYPE=Release `
      -DCMAKE_PREFIX_PATH="$($Ucrt64 -replace '\\','/')" `
      -DCMAKE_CXX_COMPILER="$($Ucrt64 -replace '\\','/')/bin/g++.exe" | Out-Null
  & cmake --build $build | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
if (-not (Test-Path "$build\r9view.exe")) { throw "no r9view.exe in $build" }

# ---- libmpv ----------------------------------------------------------------
if ($MpvDll -eq "") {
  $cache = Join-Path $Out "_mpv"
  $archive = Join-Path $cache $MpvAsset
  $MpvDll = Join-Path $cache "libmpv-2.dll"
  if (-not (Test-Path $MpvDll)) {
    Step "Fetching libmpv ($MpvAsset)"
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    $url = "https://github.com/zhongfly/mpv-winbuild/releases/download/$MpvRelease/$MpvAsset"
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    $got = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $MpvSha256) { throw "libmpv checksum mismatch`n  expected $MpvSha256`n  got      $got" }
    & "$Ucrt64\bin\bsdtar.exe" -xf $archive -C $cache libmpv-2.dll
  }
}
if (-not (Test-Path $MpvDll)) { throw "no libmpv-2.dll at $MpvDll" }

# ---- stage -----------------------------------------------------------------
Step "Staging"
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item "$build\r9view.exe" $stage
# Before windeployqt, so the dependency walk below never wanders into MSYS2's
# ffmpeg tree looking for something this DLL already contains.
Copy-Item $MpvDll $stage

Step "windeployqt"
& "$Ucrt64\bin\windeployqt.exe" --qmldir "$Source\qml" --release --no-translations `
    --no-system-d3d-compiler "$stage\r9view.exe" | Out-Null

# ---- the rest of the dependency tree ---------------------------------------
# windeployqt knows about Qt. It does not know that libarchive needs lzma, or
# that the HEIF image plugin needs libde265, so the imports are walked by hand
# and anything that lives in ucrt64\bin comes along.
Step "Resolving remaining DLLs"
$seen = @{}
$queue = [System.Collections.Queue]::new()
Get-ChildItem $stage -Recurse -Include *.exe, *.dll | ForEach-Object { $queue.Enqueue($_.FullName) }
$added = 0
while ($queue.Count -gt 0) {
  $cur = $queue.Dequeue()
  $key = Split-Path $cur -Leaf
  if ($seen.ContainsKey($key)) { continue }
  $seen[$key] = $true
  $deps = & "$Ucrt64\bin\objdump.exe" -p $cur 2>$null | Select-String 'DLL Name:' | ForEach-Object { ($_ -split '\s+')[-1] }
  foreach ($d in $deps) {
    $src = Join-Path "$Ucrt64\bin" $d
    $dst = Join-Path $stage $d
    if ((Test-Path $src) -and -not (Test-Path $dst)) {
      Copy-Item $src $dst; $added++; $queue.Enqueue($dst)
    }
  }
}
Write-Host "    $added support DLLs"

# ---- trim ------------------------------------------------------------------
# main.cpp pins QQuickStyle to Basic, so every other Controls style is dead
# weight -- and windeployqt ships all of them.
Step "Trimming"
$deadStyles = @("Fusion", "Imagine", "Material", "Universal", "FluentWinUI3", "Windows")
foreach ($s in $deadStyles) {
  Remove-Item -Recurse -Force "$stage\qml\QtQuick\Controls\$s" -ErrorAction SilentlyContinue
  Get-ChildItem $stage -Filter "Qt6QuickControls2$s*.dll" -ErrorAction SilentlyContinue | Remove-Item -Force
}
# QML debugging plugins are of no use in a release.
Remove-Item -Recurse -Force "$stage\qmltooling" -ErrorAction SilentlyContinue

# Tell Qt to look beside the executable rather than at the prefix it was built
# with. Without this the app finds MSYS2's QML modules on the build machine and
# finds nothing at all anywhere else.
@"
[Paths]
Prefix = .
Plugins = .
Imports = qml
Qml2Imports = qml
"@ | Set-Content -Path "$stage\qt.conf" -Encoding ascii

Copy-Item "$Source\LICENSE" $stage -ErrorAction SilentlyContinue
Copy-Item "$Source\README.md" $stage -ErrorAction SilentlyContinue

# ---- zip -------------------------------------------------------------------
$version = (Select-String -Path "$Source\CMakeLists.txt" -Pattern 'project\(r9view VERSION ([0-9.]+)').Matches[0].Groups[1].Value
$zip = Join-Path $Out "r9view-$version-windows-x64.zip"
Step "Zipping"
Remove-Item -Force $zip -ErrorAction SilentlyContinue
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal

# ---- setup.exe -------------------------------------------------------------
# Optional: without NSIS the zip and install.ps1 are still a complete release.
$setup = Join-Path $Out "r9view-$version-windows-x64-setup.exe"
$makensis = Join-Path $Ucrt64 "bin\makensis.exe"
if (Test-Path $makensis) {
  Step "Building setup.exe"
  Remove-Item -Force $setup -ErrorAction SilentlyContinue
  & $makensis /V2 "/DVERSION=$version" "/DSTAGE=$stage" "/DOUTFILE=$setup" "$Source\packaging\r9view.nsi"
  if ($LASTEXITCODE -ne 0) { throw "makensis failed" }
} else {
  Warn "makensis not found, skipping setup.exe (pacman -S mingw-w64-ucrt-x86_64-nsis)"
  $setup = $null
}

$mb = [math]::Round((Get-ChildItem $stage -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
$zmb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ""
Write-Host "r9view $version" -ForegroundColor Green
Write-Host "  folder  $stage  ($mb MB, $((Get-ChildItem $stage -Recurse -File).Count) files)"
Write-Host "  zip     $zip  ($zmb MB)"
Write-Host "  sha256  $((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower())"
if ($setup -and (Test-Path $setup)) {
  Write-Host "  setup   $setup  ($([math]::Round((Get-Item $setup).Length/1MB,1)) MB)"
  Write-Host "  sha256  $((Get-FileHash $setup -Algorithm SHA256).Hash.ToLower())"
}
