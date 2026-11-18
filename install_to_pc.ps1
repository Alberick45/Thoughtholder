# Reinstall ThoughtHolder on Windows PC
param(
    [switch]$LaunchAfterInstall = $false
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ThoughtHolder Clean PC Reinstall" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Terminate any running ThoughtHolder process
$running = Get-Process -Name "thought_holder_flutter" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "[1/5] Closing running ThoughtHolder processes..." -ForegroundColor Yellow
    Stop-Process -Name "thought_holder_flutter" -Force
    Start-Sleep -Seconds 1
} else {
    Write-Host "[1/5] No running ThoughtHolder processes found." -ForegroundColor Green
}

# 2. Verify source Release build
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}
$sourceDir = Join-Path $scriptRoot "thought_holder_flutter\build\windows\x64\runner\Release"

if (!(Test-Path "$sourceDir\thought_holder_flutter.exe")) {
    Write-Host "Release build not found in: $sourceDir" -ForegroundColor Red
    Write-Host "Building Windows Release now..." -ForegroundColor Yellow
    Push-Location (Join-Path $scriptRoot "thought_holder_flutter")
    & "C:\src\flutter\bin\flutter.bat" build windows --release
    Pop-Location
}

if (!(Test-Path "$sourceDir\thought_holder_flutter.exe")) {
    throw "Build failed: $sourceDir\thought_holder_flutter.exe could not be found."
}

# 3. Target directory: AppData\Local\Programs\ThoughtHolder
$installDir = Join-Path $env:LOCALAPPDATA "Programs\ThoughtHolder"
Write-Host "[2/5] Cleaning target directory: $installDir" -ForegroundColor Yellow

if (Test-Path $installDir) {
    # Remove old files to guarantee a completely clean fresh installation
    Get-ChildItem -Path $installDir -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# 4. Copy fresh release files
Write-Host "[3/5] Installing fresh release files to $installDir..." -ForegroundColor Yellow
Copy-Item -Path "$sourceDir\*" -Destination $installDir -Recurse -Force

# 5. Create / Update Desktop and Start Menu shortcuts
Write-Host "[4/5] Updating Desktop and Start Menu shortcuts..." -ForegroundColor Yellow
$targetExe = Join-Path $installDir "thought_holder_flutter.exe"

$wshShell = New-Object -ComObject WScript.Shell

# Desktop shortcut
$desktopDir = [Environment]::GetFolderPath("Desktop")
if (Test-Path $desktopDir) {
    $desktopShortcut = $wshShell.CreateShortcut((Join-Path $desktopDir "ThoughtHolder.lnk"))
    $desktopShortcut.TargetPath = $targetExe
    $desktopShortcut.WorkingDirectory = $installDir
    $desktopShortcut.Description = "ThoughtHolder"
    $desktopShortcut.Save()
}

# Start Menu shortcut
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ThoughtHolder"
if (!(Test-Path $startMenuDir)) {
    New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null
}
$startShortcut = $wshShell.CreateShortcut((Join-Path $startMenuDir "ThoughtHolder.lnk"))
$startShortcut.TargetPath = $targetExe
$startShortcut.WorkingDirectory = $installDir
$startShortcut.Description = "ThoughtHolder"
$startShortcut.Save()

# 6. Verification
Write-Host "[5/5] Verifying installation..." -ForegroundColor Green
$installedExe = Get-Item $targetExe
$installedCount = (Get-ChildItem -Path $installDir).Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  REINSTALL COMPLETE!" -ForegroundColor Green
Write-Host "  Location: $installDir" -ForegroundColor White
Write-Host "  Files installed: $installedCount items" -ForegroundColor White
Write-Host "  Executable: $($installedExe.Name) ($([math]::Round($installedExe.Length/1KB, 1)) KB)" -ForegroundColor White
Write-Host "  Last Modified: $($installedExe.LastWriteTime)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

if ($LaunchAfterInstall) {
    Write-Host "Launching updated ThoughtHolder..." -ForegroundColor Cyan
    Start-Process -FilePath $targetExe
}

