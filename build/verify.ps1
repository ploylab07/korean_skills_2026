# Repository smoke test — Windows (PowerShell)
# Terraform wrapper, env loading, init/validate/plan
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$SmokeDir = Join-Path $Root "build/smoke"

function Invoke-Terraform([string[]]$TfArgs) {
    if ($IsWindows -or ($env:OS -match "Windows")) {
        & (Join-Path $Root "terraform.cmd") @TfArgs
        return
    }
    & bash (Join-Path $Root "terraform") @TfArgs
}
$Pass = 0
$Fail = 0
$Skip = 0

function Write-Pass([string]$Name) {
    Write-Host "[OK] $Name" -ForegroundColor Green
    $script:Pass++
}

function Write-Fail([string]$Name) {
    Write-Host "[FAIL] $Name" -ForegroundColor Red
    $script:Fail++
}

function Write-Skip([string]$Name) {
    Write-Host "[SKIP] $Name" -ForegroundColor Yellow
    $script:Skip++
}

function Test-Check([string]$Name, [scriptblock]$Block) {
    try {
        if (& $Block) {
            Write-Pass $Name
        }
        else {
            Write-Fail $Name
        }
    }
    catch {
        Write-Fail $Name
    }
}

Write-Host "=== Korean Skills 2026 — smoke verify (Windows) ==="
Write-Host "root: $Root"
Write-Host ""

if ($IsWindows -or ($env:OS -match "Windows")) {
    Test-Check "terraform.cmd wrapper exists" { Test-Path (Join-Path $Root "terraform.cmd") }
}
else {
    Test-Check "terraform bash wrapper exists" { Test-Path (Join-Path $Root "terraform") }
}
Test-Check "setup-aws.cmd exists" { Test-Path (Join-Path $Root "setup-aws.cmd") }
Test-Check "build\terraform.cmd exists" { Test-Path (Join-Path $Root "build\terraform.cmd") }
Test-Check ".env.example exists" { Test-Path (Join-Path $Root ".env.example") }

try {
    $verOut = Invoke-Terraform @("version") 2>&1 | Out-String
    if ($verOut -match "Terraform v") {
        Write-Pass "terraform version runs"
    }
    else {
        Write-Fail "terraform version runs"
    }
}
catch {
    Write-Fail "terraform version runs"
}

$envFile = Join-Path $Root ".env"
if (Test-Path $envFile) {
    . (Join-Path $PSScriptRoot "load-env.ps1")
    Import-RepoEnv -BuildDir $PSScriptRoot
    if ($env:AWS_ACCESS_KEY_ID -and $env:AWS_SECRET_ACCESS_KEY) {
        Write-Pass ".env loaded (AWS_ACCESS_KEY_ID set)"
    }
    else {
        Write-Fail ".env loaded"
    }
}
else {
    Write-Skip ".env not found — run .\setup-aws.cmd first"
}

try {
    Invoke-Terraform @("-chdir=$SmokeDir", "init", "-input=false") *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "terraform init (build/smoke)"
    }
    else {
        Write-Fail "terraform init (build/smoke)"
    }
}
catch {
    Write-Fail "terraform init (build/smoke)"
}

try {
    Invoke-Terraform @("-chdir=$SmokeDir", "validate") *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "terraform validate (build/smoke)"
    }
    else {
        Write-Fail "terraform validate (build/smoke)"
    }
}
catch {
    Write-Fail "terraform validate (build/smoke)"
}

if (Test-Path $envFile) {
    . (Join-Path $PSScriptRoot "load-env.ps1")
    Import-RepoEnv -BuildDir $PSScriptRoot
    $planOut = ""
    $lockInfo = Join-Path $SmokeDir ".terraform.tfstate.lock.info"
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        if ((Test-Path $lockInfo) -and -not (Get-Process -Name "terraform*" -ErrorAction SilentlyContinue)) {
            Remove-Item -Force $lockInfo -ErrorAction SilentlyContinue
        }
        try {
            $planOut = Invoke-Terraform @("-chdir=$SmokeDir", "plan", "-input=false", "-lock=false") 2>&1 | Out-String
        }
        catch {
            $planOut = "$_"
        }
        if ($planOut -match "account_id|Plan:|No changes") { break }
        if ($planOut -match "Error acquiring the state lock|resource temporarily unavailable") {
            Start-Sleep -Seconds ($attempt * 3)
            continue
        }
        break
    }
    if ($planOut -match "account_id|Plan:|No changes") {
        Write-Pass "terraform plan (build/smoke)"
    }
    elseif ($planOut -match "InvalidClientTokenId|SignatureDoesNotMatch|UnrecognizedClientException|security token") {
        Write-Skip "terraform plan — AWS key invalid (wrapper/env OK)"
    }
    else {
        Write-Fail "terraform plan (build/smoke)"
        ($planOut -split "`n" | Select-Object -Last 20) -join "`n" | Write-Host
    }
}
else {
    Write-Skip "terraform plan — .env missing"
}

Test-Check "harness rule exists" { Test-Path (Join-Path $Root ".cursor\rules\harness-engineering.mdc") }
Test-Check "hooks.json exists" { Test-Path (Join-Path $Root ".cursor\hooks.json") }
Test-Check "run.cmd exists" { Test-Path (Join-Path $Root "run.cmd") }
Test-Check "verify.cmd exists" { Test-Path (Join-Path $Root "verify.cmd") }

Write-Host ""
Write-Host "=== result: pass=$Pass fail=$Fail skip=$Skip ==="
if ($Fail -gt 0) {
    exit 1
}
exit 0
