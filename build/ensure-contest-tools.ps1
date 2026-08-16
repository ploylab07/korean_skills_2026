# Ensure contest binaries on PATH for Windows apply.
# Encoding: UTF-8 with BOM (Windows PowerShell 5.x)

function Find-ToolPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$CandidateExes
    )
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }
    foreach ($p in $CandidateExes) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            return $p
        }
    }
    return $null
}

function Add-PathDir([string]$Dir) {
    if (-not $Dir) { return }
    if (-not (Test-Path -LiteralPath $Dir)) { return }
    $parts = @($env:PATH -split ';' | Where-Object { $_ -and $_.Trim() -ne '' })
    if ($parts -contains $Dir) { return }
    $env:PATH = "$Dir;" + $env:PATH
}

function Test-NeedsBashLocalExec([string]$RelPath) {
    # Catalog assignments with local-exec / EKS / docker build
    return ($RelPath -match '(?i)day1\\(002|007)|day2\\(002|007|008)')
}

function Test-NeedsKubectl([string]$RelPath) {
    return ($RelPath -match '(?i)day1\\(002|007)|day2\\(007|008)')
}

function Test-NeedsDocker([string]$RelPath) {
    return ($RelPath -match '(?i)day1\\(002|007)')
}

function Ensure-ContestTools {
    param(
        [string]$RelPath = ""
    )
    Write-Host ""
    Write-Host ">>> Contest tools check ($RelPath)" -ForegroundColor Cyan

    $pf = ${env:ProgramFiles}
    $pf86 = ${env:ProgramFiles(x86)}
    $local = $env:LOCALAPPDATA

    $needBash = Test-NeedsBashLocalExec $RelPath
    $needKubectl = Test-NeedsKubectl $RelPath
    $needDocker = Test-NeedsDocker $RelPath

    $aws = Find-ToolPath -Name "aws" -CandidateExes @(
        (Join-Path $pf "Amazon\AWSCLIV2\aws.exe")
        (Join-Path $pf86 "Amazon\AWSCLIV2\aws.exe")
    )
    $kubectl = $null
    $docker = $null
    $bash = $null
    if ($needKubectl) {
        $kubectl = Find-ToolPath -Name "kubectl" -CandidateExes @(
            (Join-Path $pf "Docker\Docker\resources\bin\kubectl.exe")
            (Join-Path $local "Microsoft\WinGet\Links\kubectl.exe")
        )
    }
    if ($needDocker) {
        $docker = Find-ToolPath -Name "docker" -CandidateExes @(
            (Join-Path $pf "Docker\Docker\resources\bin\docker.exe")
        )
    }
    if ($needBash) {
        $bash = Find-ToolPath -Name "bash" -CandidateExes @(
            (Join-Path $pf "Git\bin\bash.exe")
            (Join-Path $pf "Git\usr\bin\bash.exe")
            (Join-Path $pf86 "Git\bin\bash.exe")
        )
    }

    $missing = @()
    if (-not $aws) { $missing += "AWS CLI v2 (aws.exe) - https://aws.amazon.com/cli/" }
    if ($needKubectl -and -not $kubectl) { $missing += "kubectl - https://kubernetes.io/docs/tasks/tools/" }
    if ($needDocker -and -not $docker) { $missing += "Docker Desktop (docker.exe)" }
    if ($needBash -and -not $bash) { $missing += "Git for Windows (bash.exe) - https://git-scm.com/download/win" }

    if ($missing.Count -gt 0) {
        Write-Host "[!] Missing tools required for this assignment:" -ForegroundColor Red
        foreach ($m in $missing) {
            Write-Host ("    - {0}" -f $m) -ForegroundColor Yellow
        }
        Write-Host "Install them, open a NEW PowerShell, then re-run .\start.cmd" -ForegroundColor Yellow
        throw "Contest tools missing"
    }

    Add-PathDir (Split-Path -Parent $aws)
    if ($kubectl) { Add-PathDir (Split-Path -Parent $kubectl) }
    if ($docker) { Add-PathDir (Split-Path -Parent $docker) }
    if ($bash) {
        Add-PathDir (Split-Path -Parent $bash)
        $gitBin = Join-Path $pf "Git\bin"
        if (Test-Path -LiteralPath $gitBin) { Add-PathDir $gitBin }
    }

    Write-Host ("[OK] aws={0}" -f $aws) -ForegroundColor Green
    if ($needKubectl) { Write-Host ("[OK] kubectl={0}" -f $kubectl) -ForegroundColor Green }
    if ($needDocker) { Write-Host ("[OK] docker={0}" -f $docker) -ForegroundColor Green }
    if ($needBash) { Write-Host ("[OK] bash={0}" -f $bash) -ForegroundColor Green }

    & aws --version
    if ($LASTEXITCODE -ne 0) { throw "aws --version failed" }
    if ($needBash) {
        & bash -lc "echo bash-ok" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "bash smoke failed" }
    }
}
