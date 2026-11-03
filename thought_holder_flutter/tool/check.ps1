# ThoughtHolder One-Command Health Check (tool/check.ps1)
# Runs static analysis, automated unit tests, and SQLite checks on a COPY of the database.

$ErrorActionPreference = "Continue"
$failedCount = 0

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " THOUGHTHOLDER SYSTEM & DATA HEALTH CHECK" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Static Analysis
Write-Host "[1/3] Running flutter analyze..." -ForegroundColor Yellow
$analyzeOutput = & flutter analyze 2>&1
$analyzeExit = $LASTEXITCODE

if ($analyzeExit -eq 0) {
    Write-Host "[PASS] Flutter static analysis: 0 issues found" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Flutter static analysis failed" -ForegroundColor Red
    $analyzeOutput | Select-Object -Last 10 | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
    $failedCount++
}
Write-Host ""

# 2. Automated Test Suite
Write-Host "[2/3] Running automated tests (flutter test)..." -ForegroundColor Yellow
$testOutput = & flutter test 2>&1
$testExit = $LASTEXITCODE

if ($testExit -eq 0) {
    Write-Host "[PASS] Automated test suite: all tests passed" -ForegroundColor Green
    $testOutput | Select-Object -Last 3 | ForEach-Object { Write-Host "       $_" -ForegroundColor Gray }
} else {
    Write-Host "[FAIL] Automated test suite had failures" -ForegroundColor Red
    $testOutput | Select-Object -Last 15 | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
    $failedCount++
}
Write-Host ""

# 3. Data Self-Check on a COPY of the Database
Write-Host "[3/3] Running data self-check on a database COPY..." -ForegroundColor Yellow
$liveDbPath = "$env:APPDATA\com.example\ThoughtHolder\databases\thoughts.db"
$tempCopyPath = "$env:TEMP\th_check_copy_$(Get-Date -Format 'yyyyMMdd_HHmmss').db"

if (Test-Path $liveDbPath) {
    try {
        # Copy to temporary location so active database is never locked or modified
        Copy-Item -Path $liveDbPath -Destination $tempCopyPath -Force

        $dbCheckOutput = & py tool/check_db.py $tempCopyPath 2>&1
        $dbCheckExit = $LASTEXITCODE

        $dbCheckOutput | ForEach-Object {
            if ($_ -match "\[PASS\]") {
                Write-Host $_ -ForegroundColor Green
            } elseif ($_ -match "\[FAIL\]") {
                Write-Host $_ -ForegroundColor Red
            } else {
                Write-Host $_ -ForegroundColor Gray
            }
        }

        if ($dbCheckExit -ne 0) {
            $failedCount++
        }
    } catch {
        Write-Host "[FAIL] Could not copy and inspect database: $_" -ForegroundColor Red
        $failedCount++
    } finally {
        if (Test-Path $tempCopyPath) {
            Remove-Item -Path $tempCopyPath -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "[WARN] Live database not found at $liveDbPath (fresh install mode)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
if ($failedCount -eq 0) {
    Write-Host " OVERALL RESULT: ALL CHECKS PASSED [PASS]" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host " OVERALL RESULT: $failedCount ITEM(S) FAILED [FAIL]" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Cyan
    exit 1
}
