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

    $lines = @($output | ForEach-Object { [string]$_ })
    foreach ($line in $lines) {
        Write-Host $line
    }

    # Persist last run for apply-failure diagnosis (wipe/destroy scrolls Error: away)
    $logPath = Join-Path $BuildDir "last-terraform.log"
    try {
        $header = @(
            ("# {0}" -f (Get-Date -Format "o"))
            ("# RUN: {0} {1}" -f $exe, ($allArgs -join ' '))
            ("# exit={0}" -f $code)
            ""
        )
        ($header + $lines) | Set-Content -LiteralPath $logPath -Encoding UTF8
    }
    catch {
        Write-Warn ("could not write {0}: {1}" -f $logPath, $_)
    }

    return [int]$code
}

function Show-LastTerraformErrors {
    $logPath = Join-Path $BuildDir "last-terraform.log"
    Write-Host ""
    Write-Host "======== terraform Error summary ========" -ForegroundColor Red
    if (-not (Test-Path -LiteralPath $logPath)) {
        Write-Host "(no build\last-terraform.log yet)" -ForegroundColor Yellow
        return
    }
    $errs = Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'Error:|error:|Failed|failed' }
    if (-not $errs) {
        Write-Host "(no Error: lines found — open build\last-terraform.log)" -ForegroundColor Yellow
    }
    else {
        $errs | Select-Object -Last 40 | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }
    Write-Host ""
    Write-Host "--- last 35 log lines ---" -ForegroundColor DarkGray
    Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue |
        Select-Object -Last 35 |
        ForEach-Object { Write-Host $_ }
    Write-Host ("Full log: {0}" -f $logPath) -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Red
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

function Prompt-DeployMode {
    Write-Host ""
    Write-Host "=== Deploy mode ===" -ForegroundColor Cyan
    Write-Host "  [1] Apply only"
    Write-Host "  [2] Destroy only (cleanup state resources)"
    Write-Host "  [3] Destroy then Apply (clean redeploy)"
    while ($true) {
        $choice = Read-Host "Select mode"
        switch ($choice) {
            "1" { return "apply" }
            "2" { return "destroy" }
            "3" { return "destroy-apply" }
            default { Write-Warn "Invalid selection." }
        }
    }
}

function Invoke-Destroy([string]$AssignPath, [string]$RelPath) {
    Write-Host "Will run: terraform destroy -auto-approve for $RelPath" -ForegroundColor Yellow
    Write-Host "This deletes resources tracked in this folder's terraform state." -ForegroundColor Yellow
    $confirm = Read-Host "Continue destroy? [y/N]"
    if ($confirm -notmatch '^[Yy]') {
        Write-Warn "Destroy cancelled"
        return $false
    }
    Invoke-TerraformRetry -AssignPath $AssignPath -TfArgs @("init", "-input=false") -Label "terraform init" -MaxAttempts 3
    $code = [int](Invoke-RepoTerraform -Chdir $AssignPath -TfArgs @("destroy", "-input=false", "-auto-approve"))
    if ($code -ne 0) {
        Write-Warn "terraform destroy failed (exit $code) - will still try AWS name-based wipe if day1/002"
    }
    else {
        Write-Ok "Destroy done: $RelPath"
    }

    # Partial state often leaves SameName leftovers; wipe by known names for day1/002
    if ($RelPath -match '(?i)day1\\002') {
        $wipe = Read-Host "Also wipe AWS leftovers named wskorea26-* (recommended)? [Y/n]"
        if ($wipe -notmatch '^[Nn]') {
            . (Join-Path $BuildDir "cleanup-wskorea26.ps1")
            $region = if ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { "ap-northeast-2" }
            Clear-Wskorea26Leftovers -Region $region
        }
    }
    else {
        Write-Host "Note: only resources in THIS folder terraform state were deleted." -ForegroundColor Yellow
        Write-Host "If apply fails with AlreadyExists, clean leftover AWS resources then retry." -ForegroundColor Yellow
    }
    return $true
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

function Test-TfStateHas([string]$AssignPath, [string]$Address) {
    $exe = [string](Get-TerraformExe)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $list = @(& $exe "-chdir=$AssignPath" "state" "list" 2>$null)
    $ErrorActionPreference = $prev
    return ($list | ForEach-Object { "$_".Trim() }) -contains $Address
}

function Invoke-TfImportQuiet {
    param([string]$AssignPath, [string]$Address, [string]$Id)
    if (-not $Id) {
        Write-Host ("  skip import {0} (not found in AWS)" -f $Address) -ForegroundColor DarkYellow
        return
    }
    if (Test-TfStateHas -AssignPath $AssignPath -Address $Address) { return }
    Write-Host ("  import {0} <= {1}" -f $Address, $Id) -ForegroundColor Cyan
    $code = [int](Invoke-RepoTerraform -Chdir $AssignPath -TfArgs @("import", "-input=false", $Address, $Id))
    if ($code -ne 0) {
        Write-Warn ("import failed: {0}" -f $Address)
    }
}

function Import-Day1002Orphans([string]$AssignPath) {
    Write-Host ">>> Adopt leftover AWS names into terraform state (avoids 409 AlreadyExists)" -ForegroundColor Cyan
    . (Join-Path $BuildDir "cleanup-wskorea26.ps1")
    $bucket = Get-AwsText s3api list-buckets --query "Buckets[?starts_with(Name, 'wskorea26-concert-bucket-')].Name | [0]" --output text
    Invoke-TfImportQuiet -AssignPath $AssignPath -Address "aws_s3_bucket.web" -Id $bucket
    Invoke-TfImportQuiet -AssignPath $AssignPath -Address "aws_cloudfront_function.rewrite" -Id "wskorea26-book-rewrite"
    $oac = Get-AwsText cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='wskorea26-s3-oac'].Id" --output text
    $oacId = (@($oac -split '\s+') | Where-Object { $_ }) | Select-Object -First 1
    Invoke-TfImportQuiet -AssignPath $AssignPath -Address "aws_cloudfront_origin_access_control.s3" -Id $oacId
    Invoke-TfImportQuiet -AssignPath $AssignPath -Address "module.book_image.aws_cloudwatch_log_group.build" -Id "/codebuild/wskorea26-book"
    $dist = Get-AwsText cloudfront list-distributions --query "DistributionList.Items[?Comment=='wskorea26-concert-cf'].Id" --output text
    $distId = (@($dist -split '\s+') | Where-Object { $_ }) | Select-Object -First 1
    Invoke-TfImportQuiet -AssignPath $AssignPath -Address "aws_cloudfront_distribution.main" -Id $distId
}

function Invoke-Day1003PostDeploy([string]$AssignPath) {
    Write-Step "day1/003 post-deploy (k8s apps + CloudFront)"
    Write-Host "start.cmd only runs Terraform. day1/003 also needs deploy.sh for mark 4-2/5/11." -ForegroundColor Yellow

    $deploySh = Join-Path $AssignPath "scripts\deploy.sh"
    if (-not (Test-Path -LiteralPath $deploySh)) {
        throw "Missing $deploySh"
    }

    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) {
        $bashExe = $bash.Source
    }
    else {
        $bashExe = Join-Path ${env:ProgramFiles} "Git\bin\bash.exe"
    }
    if (-not (Test-Path -LiteralPath $bashExe)) {
        throw "Git Bash required for day1/003 deploy.sh"
    }

    Write-Host ("RUN: {0} {1}" -f $bashExe, $deploySh) -ForegroundColor Cyan
    & $bashExe $deploySh
    if ($LASTEXITCODE -ne 0) {
        throw ("deploy.sh failed (exit {0})" -f $LASTEXITCODE)
    }
    Write-Ok "day1/003 post-deploy done"
}

function Invoke-Apply([string]$RelPath, [string]$AssignPath) {
    Write-Step "5/5 Deploy (apply) - $RelPath"

    Write-Host "Will run: init -> validate -> plan -> apply" -ForegroundColor Yellow
    Write-Host "Providers: offline mirror under build\tf-mirror" -ForegroundColor Cyan
    Write-Host "Tip: if names already exist in AWS, use mode [3] Destroy then Apply" -ForegroundColor Cyan
    $confirm = Read-Host "Continue apply? [Y/n]"
    if ($confirm -match '^[Nn]') {
        Write-Warn "Cancelled"
        return $false
    }

    Invoke-TerraformRetry -AssignPath $AssignPath -TfArgs @("init", "-input=false") -Label "terraform init" -MaxAttempts 3

    if ($RelPath -match '(?i)day1\\002') {
        Import-Day1002Orphans -AssignPath $AssignPath
    }

    $code = [int](Invoke-RepoTerraform -Chdir $AssignPath -TfArgs @("validate"))
    if ($code -ne 0) { throw "terraform validate failed" }

    $code = [int](Invoke-RepoTerraform -Chdir $AssignPath -TfArgs @("plan", "-input=false"))
    if ($code -ne 0) { throw "terraform plan failed" }

    $code = [int](Invoke-RepoTerraform -Chdir $AssignPath -TfArgs @("apply", "-input=false", "-auto-approve"))
    if ($code -ne 0) {
        Write-Warn "terraform apply failed (exit $code)"
        Show-LastTerraformErrors
        Write-Host "Paste the Error summary above (or build\last-terraform.log) if you need help." -ForegroundColor Yellow
        Write-Host "Partial resources may remain. Recommended: destroy (+ wskorea26 wipe) then retry." -ForegroundColor Yellow
        $ans = Read-Host "Run terraform destroy now? [Y/n]"
        if ($ans -notmatch '^[Nn]') {
            $null = Invoke-Destroy -AssignPath $AssignPath -RelPath $RelPath
            $retry = Read-Host "Retry apply now? [Y/n]"
            if ($retry -notmatch '^[Nn]') {
                Write-Host "Retrying apply (init skipped)..." -ForegroundColor Cyan
                if ($RelPath -match '(?i)day1\\002') {
                    Import-Day1002Orphans -AssignPath $AssignPath
                }
                $code = [int](Invoke-RepoTerraform -Chdir $AssignPath -TfArgs @("apply", "-input=false", "-auto-approve"))
                if ($code -eq 0) {
                    if ($RelPath -match '(?i)day1\\003') {
                        Invoke-Day1003PostDeploy -AssignPath $AssignPath
                    }
                    Write-Ok "Deploy done: $RelPath"
                    return $true
                }
                Show-LastTerraformErrors
            }
        }
        throw "terraform apply failed — see build\last-terraform.log"
    }

    if ($RelPath -match '(?i)day1\\003') {
        Invoke-Day1003PostDeploy -AssignPath $AssignPath
    }

    Write-Ok "Deploy done: $RelPath"
    return $true
}

function Invoke-Assignment([string]$RelPath) {
    Write-Step "5/5 Assignment - $RelPath"
    if ($Root -match 'korean_skills_2026-master') {
        Write-Warn "GitHub ZIP folder detected (korean_skills_2026-master). Fixes may be missing."
        Write-Host "  Use: git clone https://github.com/ploylab07/korean_skills_2026.git" -ForegroundColor Yellow
        Write-Host "  Then: git pull origin master" -ForegroundColor Yellow
    }
    $assignPath = Resolve-AssignmentPath $RelPath

    . (Join-Path $BuildDir "ensure-contest-tools.ps1")
    Ensure-ContestTools -RelPath $RelPath

    $mode = Prompt-DeployMode
    switch ($mode) {
        "destroy" {
            $ok = Invoke-Destroy -AssignPath $assignPath -RelPath $RelPath
            if (-not $ok) { throw "destroy aborted or failed" }
        }
        "destroy-apply" {
            $ok = Invoke-Destroy -AssignPath $assignPath -RelPath $RelPath
            if (-not $ok) { throw "destroy aborted or failed - apply skipped" }
            $null = Invoke-Apply -RelPath $RelPath -AssignPath $assignPath
        }
        default {
            $null = Invoke-Apply -RelPath $RelPath -AssignPath $assignPath
        }
    }
}

# --- main ---
Set-Location $Root
Write-Host "=== Korean Skills 2026 - contest deploy ===" -ForegroundColor Cyan
Write-Host "root: $Root"

Ensure-Prerequisites
Ensure-TerraformBinary
Ensure-AwsEnv
$path = Prompt-Folder
Invoke-Assignment -RelPath $path

Write-Host ""
Write-Host "=== Deploy finished ===" -ForegroundColor Green
exit 0
