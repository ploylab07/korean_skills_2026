# Windows one-click deploy - .\start.cmd
# 1) PowerShell/network  2) Terraform  3) .env  4) pick assignment  5) apply
# Encoding: UTF-8 with BOM (required for Windows PowerShell 5.x)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $Root "build"
$TfCmd = Join-Path $Root "terraform.cmd"
$EnvFile = Join-Path $Root ".env"

$Catalog = @(
    @{ Id = "1"; Path = "day1\002"; Label = "day1 / 002" }
    @{ Id = "2"; Path = "day1\003"; Label = "day1 / 003" }
    @{ Id = "3"; Path = "day1\006"; Label = "day1 / 006" }
    @{ Id = "4"; Path = "day1\007"; Label = "day1 / 007" }
    @{ Id = "5"; Path = "day2\002"; Label = "day2 / 002" }
    @{ Id = "6"; Path = "day2\007"; Label = "day2 / 007" }
    @{ Id = "7"; Path = "day2\008"; Label = "day2 / 008" }
)

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ">>> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Ensure-Prerequisites {
    Write-Step "1/5 PowerShell / network check"

    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5) {
        throw "PowerShell 5.0+ required. Current: $psVer"
    }
    Write-Ok "PowerShell $psVer"

    try {
        $null = Invoke-WebRequest -Uri "https://releases.hashicorp.com" -Method Head -UseBasicParsing -TimeoutSec 10
        Write-Ok "Network OK"
    }
    catch {
        throw "Internet required (Terraform download)."
    }
}

function Ensure-TerraformBinary {
    Write-Step "2/5 Terraform check/install"
    if (-not (Test-Path $TfCmd)) {
        throw "terraform.cmd not found: $TfCmd"
    }
    & $TfCmd version
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform failed"
    }
    Write-Ok "Terraform ready"
}

function Ensure-AwsEnv {
    Write-Step "3/5 AWS .env setup"

    if (Test-Path $EnvFile) {
        . (Join-Path $BuildDir "load-env.ps1")
        Import-RepoEnv -BuildDir $BuildDir
        if ($env:AWS_ACCESS_KEY_ID -and $env:AWS_SECRET_ACCESS_KEY) {
            Write-Ok ".env found (region=$($env:AWS_DEFAULT_REGION))"
            $ans = Read-Host "Re-enter keys? [y/N]"
            if ($ans -notmatch '^[Yy]') {
                return
            }
        }
    }

    Write-Host "Enter AWS Access Key / Secret / Region." -ForegroundColor Yellow
    & (Join-Path $BuildDir "setup-aws.ps1")
    . (Join-Path $BuildDir "load-env.ps1")
    Import-RepoEnv -BuildDir $BuildDir
    if (-not ($env:AWS_ACCESS_KEY_ID -and $env:AWS_SECRET_ACCESS_KEY)) {
        throw ".env setup failed"
    }
    Write-Ok ".env saved"
}

function Resolve-AssignmentPath([string]$RelPath) {
    $full = Join-Path $Root $RelPath
    if (-not (Test-Path $full)) {
        throw "Assignment folder missing: $RelPath"
    }
    $tf = Get-ChildItem -Path $full -Filter "*.tf" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.terraform\\' }
    if (-not $tf) {
        throw "No .tf files in: $RelPath"
    }
    return (Resolve-Path $full).Path
}

function Prompt-Folder {
    Write-Step "4/5 Select assignment"
    Write-Host "=== Assignments ===" -ForegroundColor Cyan
    foreach ($item in $Catalog) {
        $exists = Test-Path (Join-Path $Root $item.Path)
        Write-Host ("  [{0}] {1}{2}" -f $item.Id, $item.Label, $(if ($exists) { "" } else { "  (missing)" }))
    }
    Write-Host "  [0] Exit"

    while ($true) {
        $choice = Read-Host "Select number"
        if ($choice -eq "0") { exit 0 }
        $item = $Catalog | Where-Object { $_.Id -eq $choice } | Select-Object -First 1
        if ($item) { return $item.Path }
        Write-Warn "Invalid selection."
    }
}

function Invoke-TerraformRetry {
    param(
        [string]$AssignPath,
        [string[]]$TfArgs,
        [string]$Label,
        [int]$MaxAttempts = 5
    )
    # Provider download from releases.hashicorp.com can EOF on flaky networks
    if (-not $env:TF_REGISTRY_CLIENT_TIMEOUT) {
        $env:TF_REGISTRY_CLIENT_TIMEOUT = "180"
    }
    $attempt = 0
    while ($true) {
        $attempt++
        Write-Host ("[{0}] {1} (attempt {2}/{3})" -f $Label, ($TfArgs -join ' '), $attempt, $MaxAttempts) -ForegroundColor Yellow
        & $TfCmd -chdir="$AssignPath" @TfArgs
        if ($LASTEXITCODE -eq 0) { return }
        if ($attempt -ge $MaxAttempts) {
            throw ("{0} failed after {1} attempts (exit {2})" -f $Label, $MaxAttempts, $LASTEXITCODE)
        }
        Write-Warn ("{0} failed - network/provider download? retry in {1}s..." -f $Label, (5 * $attempt))
        Start-Sleep -Seconds (5 * $attempt)
    }
}

function Invoke-Apply([string]$RelPath) {
    Write-Step "5/5 Deploy (apply) - $RelPath"
    $assignPath = Resolve-AssignmentPath $RelPath

    Write-Host "Will run: init -> validate -> plan -> apply" -ForegroundColor Yellow
    $confirm = Read-Host "Continue? [Y/n]"
    if ($confirm -match '^[Nn]') {
        Write-Warn "Cancelled"
        exit 0
    }

    # init downloads providers - retry on EOF / flaky HashiCorp CDN
    Invoke-TerraformRetry -AssignPath $assignPath -TfArgs @("init", "-input=false") -Label "terraform init" -MaxAttempts 5

    & $TfCmd -chdir="$assignPath" validate
    if ($LASTEXITCODE -ne 0) { throw "terraform validate failed" }

    & $TfCmd -chdir="$assignPath" plan "-input=false"
    if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }

    & $TfCmd -chdir="$assignPath" apply "-input=false" -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }

    Write-Ok "Deploy done: $RelPath"
}

# --- main ---
Set-Location $Root
Write-Host "=== Korean Skills 2026 - contest deploy ===" -ForegroundColor Cyan
Write-Host "root: $Root"

Ensure-Prerequisites
Ensure-TerraformBinary
Ensure-AwsEnv
$path = Prompt-Folder
Invoke-Apply -RelPath $path

Write-Host ""
Write-Host "=== Deploy finished ===" -ForegroundColor Green
exit 0
