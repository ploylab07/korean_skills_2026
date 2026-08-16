# Windows one-click deploy - .\start.cmd
# 1) PowerShell/network  2) Terraform  3) .env  4) pick assignment  5) apply
# Encoding: UTF-8 with BOM (required for Windows PowerShell 5.x)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $Root "build"
$TfCmd = Join-Path $Root "terraform.cmd"
$TfExe = Join-Path $BuildDir ".bin\terraform.exe"
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

function Get-TerraformExe {
    if (-not (Test-Path $TfExe)) {
        # Triggers download via wrapper (terraform.ps1)
        & $TfCmd version | Out-Null
    }
    if (-not (Test-Path $TfExe)) {
        throw "terraform.exe not found: $TfExe"
    }
    return [string]$TfExe
}

function Invoke-RepoTerraform {
    param(
        [Parameter(Mandatory = $true)][string]$Chdir,
        [Parameter(Mandatory = $true)][string[]]$TfArgs
    )
    $exe = [string](Get-TerraformExe)
    $allArgs = @("-chdir=$Chdir") + $TfArgs
    Write-Host ("RUN: {0} {1}" -f $exe, ($allArgs -join ' '))
    Write-Host ("TF_CLI_CONFIG_FILE={0}" -f $env:TF_CLI_CONFIG_FILE)

    # Capture stdout/stderr so they are NOT returned as function output (avoids System.Object[])
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $exe @allArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($null -eq $code) { $code = 0 }

    foreach ($line in @($output)) {
        Write-Host ([string]$line)
    }

    return [int]$code
}

function Ensure-Prerequisites {
    Write-Step "1/5 PowerShell / network check"

    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5) {
        throw "PowerShell 5.0+ required. Current: $psVer"
    }
    Write-Ok "PowerShell $psVer"

    $mirror = Join-Path $BuildDir "tf-mirror"
    if (Test-Path $mirror) {
        Write-Ok "Offline provider mirror present"
        return
    }

    try {
        $null = Invoke-WebRequest -Uri "https://releases.hashicorp.com" -Method Head -UseBasicParsing -TimeoutSec 10
        Write-Ok "Network OK"
    }
    catch {
        throw "Internet required (Terraform/provider download) or missing build/tf-mirror."
    }
}

function Ensure-TerraformBinary {
    Write-Step "2/5 Terraform + provider mirror"
    if (-not (Test-Path $TfCmd)) {
        throw "terraform.cmd not found: $TfCmd"
    }
    # ensure-tf-mirror.ps1 is also loaded by terraform.ps1; call explicitly for clear logs
    . (Join-Path $BuildDir "ensure-tf-mirror.ps1")
    $null = Get-TerraformExe
    & (Get-TerraformExe) version
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform failed"
    }
    Write-Ok "Terraform ready (mirror mode)"
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
        [int]$MaxAttempts = 3
    )
    if (-not $env:TF_REGISTRY_CLIENT_TIMEOUT) {
        $env:TF_REGISTRY_CLIENT_TIMEOUT = "180"
    }
    $attempt = 0
    while ($true) {
        $attempt++
        Write-Host ("[{0}] {1} (attempt {2}/{3})" -f $Label, ($TfArgs -join ' '), $attempt, $MaxAttempts) -ForegroundColor Yellow
        $code = [int](Invoke-RepoTerraform -Chdir $AssignPath -TfArgs $TfArgs)
        if ($code -eq 0) { return }
        if ($attempt -ge $MaxAttempts) {
            throw ("{0} failed after {1} attempts (exit {2})" -f $Label, $MaxAttempts, $code)
        }
        Write-Warn ("{0} failed (exit {1}) - retry in {2}s..." -f $Label, $code, (5 * $attempt))
        Start-Sleep -Seconds (5 * $attempt)
    }
}

function Invoke-Apply([string]$RelPath) {
    Write-Step "5/5 Deploy (apply) - $RelPath"
    $assignPath = Resolve-AssignmentPath $RelPath

    # day1/002(+EKS) needs aws/kubectl/docker/bash on PATH for local-exec + k8s provider
    . (Join-Path $BuildDir "ensure-contest-tools.ps1")
    Ensure-ContestTools

    Write-Host "Will run: init -> validate -> plan -> apply" -ForegroundColor Yellow
    Write-Host "Providers: offline mirror under build\tf-mirror" -ForegroundColor Cyan
    $confirm = Read-Host "Continue? [Y/n]"
    if ($confirm -match '^[Nn]') {
        Write-Warn "Cancelled"
        exit 0
    }

    Invoke-TerraformRetry -AssignPath $assignPath -TfArgs @("init", "-input=false") -Label "terraform init" -MaxAttempts 3

    $code = Invoke-RepoTerraform -Chdir $assignPath -TfArgs @("validate")
    if ($code -ne 0) { throw "terraform validate failed" }

    $code = Invoke-RepoTerraform -Chdir $assignPath -TfArgs @("plan", "-input=false")
    if ($code -ne 0) { throw "terraform plan failed" }

    $code = Invoke-RepoTerraform -Chdir $assignPath -TfArgs @("apply", "-input=false", "-auto-approve")
    if ($code -ne 0) { throw "terraform apply failed" }

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
