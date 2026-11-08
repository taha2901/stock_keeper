# Builds the Windows release and packs it into a single Setup.exe.
# Usage (from anywhere):  powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
# To ship an update, bump "version:" in pubspec.yaml first.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# Version comes from pubspec.yaml ("0.1.0+1" becomes "0.1.0").
$line = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)' | Select-Object -First 1
if (-not $line) { throw 'Could not read version from pubspec.yaml' }
$version = $line.Matches[0].Groups[1].Value

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 is not installed' }

Write-Host "Building version $version..."
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

# Copy the VC++ runtime the app links against from the Visual Studio redist.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -property installationPath
$crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) { throw 'VC++ redistributable files not found in Visual Studio' }

$dest = Join-Path $root 'build\installer\vcruntime'
New-Item -ItemType Directory -Force $dest | Out-Null
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item (Join-Path $crt.FullName $dll) $dest -Force
}

& $iscc /Qp "/DAppVersion=$version" installer\stock_keeper.iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compile failed' }

Write-Host "Done: $root\build\installer\StockKeeper-Setup-$version.exe"
