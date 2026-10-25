<#
.SYNOPSIS
  Runs every automated check for SketchDuel in one go.

.DESCRIPTION
  Backend : lint (ruff) + all tests (pytest)
  Flutter : pub get + static analysis + all tests
  Safety  : makes sure backend/.env (your secret keys) is not tracked by git

.EXAMPLE
  .\scripts\verify.ps1              # everything
  .\scripts\verify.ps1 -Backend     # backend only
  .\scripts\verify.ps1 -Flutter     # Flutter only
  .\scripts\verify.ps1 -Live        # also play a real match against your Supabase project
#>
[CmdletBinding()]
param(
    [switch]$Backend,
    [switch]$Flutter,
    [switch]$Live
)

$root = Split-Path -Parent $PSScriptRoot
$runBackend = $Backend -or (-not $Flutter)
$runFlutter = $Flutter -or (-not $Backend)
$results = New-Object System.Collections.ArrayList

function Invoke-Step {
    param(
        [string]$Name,
        [string]$WorkDir,
        [scriptblock]$Command
    )
    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $global:LASTEXITCODE = 0
    $passed = $false
    Push-Location $WorkDir
    try {
        & $Command
        $passed = ($global:LASTEXITCODE -eq 0)
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
    $watch.Stop()
    [void]$results.Add([pscustomobject]@{
        Step    = $Name
        Result  = if ($passed) { 'PASS' } else { 'FAIL' }
        Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
    })
}

function Fail-Step([string]$Message) {
    Write-Host $Message -ForegroundColor Red
    $global:LASTEXITCODE = 1
}

# ---------------------------------------------------------------- where things are
$backendDir = Join-Path $root 'backend'
$frontendDir = Join-Path $root 'frontend'
$python = Join-Path (Join-Path (Join-Path $backendDir 'venv') 'Scripts') 'python.exe'
$modelFile = Join-Path (Join-Path $backendDir 'models') 'quickdraw.onnx'

Write-Host "SketchDuel verification" -ForegroundColor Green
if (Test-Path $modelFile) {
    $kb = [math]::Round((Get-Item $modelFile).Length / 1KB)
    Write-Host "  ML model : trained ($kb KB) - the game uses the real classifier"
}
else {
    Write-Host "  ML model : not trained yet - the game uses the demo AI (see backend/scripts/train_quickdraw.py)"
}

# ---------------------------------------------------------------- safety
Invoke-Step 'Secrets: backend/.env is not tracked by git' $root {
    $tracked = git ls-files backend/.env 2>$null
    if ($tracked) {
        Fail-Step 'backend/.env is tracked by git! Run: git rm --cached backend/.env  (and rotate your keys if it was ever pushed)'
    }
    else {
        Write-Host 'OK'
    }
}

# ---------------------------------------------------------------- backend
if ($runBackend) {
    if (-not (Test-Path $python)) {
        Invoke-Step 'Backend: virtual environment exists' $root {
            Fail-Step "Missing $python. Create it with: python -m venv backend\venv ; backend\venv\Scripts\python.exe -m pip install -r backend\requirements-dev.txt"
        }
    }
    else {
        Invoke-Step 'Backend: lint (ruff)' $backendDir {
            & $python -m ruff check app tests scripts --select E9,F
        }
        Invoke-Step 'Backend: tests (pytest)' $backendDir {
            & $python -m pytest
        }
        if ($Live) {
            Invoke-Step 'Backend: live match against your Supabase project' $backendDir {
                & $python -W ignore scripts/live_smoke_test.py
            }
        }
    }
}

# ---------------------------------------------------------------- flutter
if ($runFlutter) {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Invoke-Step 'Flutter: tool is installed' $root {
            Fail-Step 'The flutter command was not found. Install Flutter or add it to your PATH.'
        }
    }
    else {
        Invoke-Step 'Flutter: dependencies (pub get)' $frontendDir {
            flutter pub get
        }
        Invoke-Step 'Flutter: static analysis' $frontendDir {
            flutter analyze --no-pub
        }
        Invoke-Step 'Flutter: tests' $frontendDir {
            flutter test --no-pub
        }
    }
}

# ---------------------------------------------------------------- summary
Write-Host ""
Write-Host "================ SUMMARY ================" -ForegroundColor Green
foreach ($r in $results) {
    $color = if ($r.Result -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host ("{0,-4}  {1,-52} {2,7}s" -f $r.Result, $r.Step, $r.Seconds) -ForegroundColor $color
}

$failed = @($results | Where-Object { $_.Result -eq 'FAIL' })
Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "All $($results.Count) checks passed." -ForegroundColor Green
    exit 0
}
Write-Host "$($failed.Count) of $($results.Count) checks FAILED. Scroll up to see why." -ForegroundColor Red
exit 1