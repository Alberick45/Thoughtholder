param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Version,
    [Parameter(Mandatory=$false)]
    [int]$BuildNumber
)

if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Host "Usage: .\tool\release.ps1 -Version <1.x.y> [-BuildNumber <n>]" -ForegroundColor Yellow
    exit 1
}

$PubspecPath = Join-Path $PSScriptRoot "..\pubspec.yaml"
if (-not (Test-Path $PubspecPath)) {
    Write-Error "pubspec.yaml not found at $PubspecPath"
    exit 1
}

$Content = Get-Content $PubspecPath -Raw
if ($Content -match 'version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
    $OldVersion = $Matches[1]
    $OldBuild = [int]$Matches[2]
} else {
    Write-Error "Could not parse current version in pubspec.yaml"
    exit 1
}

$NewBuild = if ($BuildNumber) { $BuildNumber } else { $OldBuild + 1 }
$NewVersionString = "$Version+$NewBuild"

Write-Host "Bumping version from $OldVersion+$OldBuild to $NewVersionString..." -ForegroundColor Cyan

# Update pubspec.yaml
$UpdatedContent = $Content -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $NewVersionString"
Set-Content -Path $PubspecPath -Value $UpdatedContent -NoNewline

# Update Inno Setup script if present
$IssPath = Join-Path $PSScriptRoot "..\windows\installer\thought_holder_setup.iss"
if (Test-Path $IssPath) {
    $IssContent = Get-Content $IssPath -Raw
    $UpdatedIss = $IssContent -replace '#define MyAppVersion "[^"]+"', "#define MyAppVersion `"$Version`""
    Set-Content -Path $IssPath -Value $UpdatedIss -NoNewline
}

Write-Host "Staging changes for git..." -ForegroundColor Cyan
git add pubspec.yaml
if (Test-Path $IssPath) {
    git add windows/installer/thought_holder_setup.iss
}

$CommitMsg = "chore(release): bump version to v$Version+$NewBuild"
Write-Host "Committing: $CommitMsg" -ForegroundColor Cyan
git commit -m $CommitMsg

$TagName = "v$Version"
Write-Host "Tagging: $TagName" -ForegroundColor Cyan
git tag -a $TagName -m "Release $TagName"

Write-Host "`nRelease tagged successfully!" -ForegroundColor Green
Write-Host "To trigger GitHub Actions build and release, run:" -ForegroundColor Yellow
Write-Host "  git push origin main; git push origin $TagName" -ForegroundColor White

