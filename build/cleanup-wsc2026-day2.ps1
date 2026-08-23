# Wipe day2/002 AWS leftovers not in terraform state (partial apply / retry).
# Encoding: UTF-8 with BOM (Windows PowerShell 5.x)

. (Join-Path $PSScriptRoot "cleanup-wskorea26.ps1")

function Remove-Wsc2026Day2OrphanAws {
    param([string]$AssignPath = "")

    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Host "[!] aws CLI not found - skip day2/002 orphan cleanup" -ForegroundColor Yellow
        return
    }

    $inState = {
        param($addr)
        if (-not $AssignPath) { return $false }
        $root = Split-Path -Parent $PSScriptRoot
        $tf = Join-Path $root "terraform.cmd"
        if (-not (Test-Path -LiteralPath $tf)) { return $false }
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $list = @(& $tf "-chdir=$AssignPath" "state" "list" 2>$null)
        $ErrorActionPreference = $prev
        return ($list | ForEach-Object { "$_".Trim() }) -contains $addr
    }

    Write-Host ">>> day2/002 orphan cleanup (state 외 동명 AWS 리소스)" -ForegroundColor Cyan

    # MSK configuration (ap-northeast-1) — ConflictException on re-apply
    if (-not (& $inState "module.msk.aws_msk_configuration.cluster")) {
        $cfgArn = Get-AwsText kafka list-configurations --region ap-northeast-1 `
            --query "Configurations[?Name=='wsc2026-msk-configuration'].Arn | [0]" --output text
        if ($cfgArn) {
            Write-Host "  delete orphan MSK configuration $cfgArn"
            $null = Invoke-AwsQuiet kafka delete-configuration --region ap-northeast-1 --arn $cfgArn
        }
    }

    # MSK cluster stuck without state (rare)
    if (-not (& $inState "module.msk.aws_msk_cluster.this")) {
        $clusterArn = Get-AwsText kafka list-clusters --region ap-northeast-1 `
            --cluster-name-filter wsc2026-msk-cluster `
            --query "ClusterInfoList[0].ClusterArn" --output text
        if ($clusterArn) {
            Write-Host "  delete orphan MSK cluster $clusterArn"
            $null = Invoke-AwsQuiet kafka delete-cluster --region ap-northeast-1 --cluster-arn $clusterArn
        }
    }
}

function Ensure-Day2002Tfvars {
    param([string]$AssignPath)

    $tfvars = Join-Path $AssignPath "terraform.tfvars"
    $bad = $false
    if (-not (Test-Path -LiteralPath $tfvars)) {
        $bad = $true
    }
    else {
        $raw = Get-Content -LiteralPath $tfvars -Raw -ErrorAction SilentlyContinue
        if (-not $raw -or $raw -match 'participant_id\s*=\s*"001"') {
            $bad = $true
        }
    }

    if (-not $bad) { return }

    # Prefer PARTICIPANT_ID / TF_VAR_participant_id from .env (cross-machine, no prompt).
    $fromEnv = $env:PARTICIPANT_ID
    if (-not $fromEnv) { $fromEnv = $env:TF_VAR_participant_id }
    if ($fromEnv -and $fromEnv -ne "001" -and $fromEnv -match '^[0-9A-Za-z-]{1,20}$') {
        @(
            "# Auto-created from .env PARTICIPANT_ID"
            "participant_id = `"$fromEnv`""
        ) | Set-Content -LiteralPath $tfvars -Encoding UTF8
        Write-Host "[OK] Wrote $tfvars from .env PARTICIPANT_ID=$fromEnv" -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "day2/002 needs participant_id (S3 suffix)." -ForegroundColor Yellow
    Write-Host "Set PARTICIPANT_ID in .env, or create terraform.tfvars (see terraform.tfvars.example)." -ForegroundColor Yellow
    Write-Host "Do NOT use 001 — S3 bucket names are globally unique and 001 is taken." -ForegroundColor Yellow
    while ($true) {
        $num = Read-Host "participant_id (your contest number)"
        if ($num -eq "001") {
            Write-Host "[!] 001 causes BucketAlreadyExists — use your assigned number" -ForegroundColor Yellow
            continue
        }
        if ($num -match '^[0-9A-Za-z-]{1,20}$') {
            @(
                "# Auto-created by start.cmd — change to your contest number if wrong"
                "participant_id = `"$num`""
            ) | Set-Content -LiteralPath $tfvars -Encoding UTF8
            Write-Host "[OK] Wrote $tfvars" -ForegroundColor Green
            return
        }
        Write-Host "[!] Invalid format (1-20 chars: letters, digits, hyphen)" -ForegroundColor Yellow
    }
}
