# Ensure aws / kubectl / docker / bash are on PATH for Windows contest apply.
# day1/002 local-exec and kubernetes/helm providers need these binaries.
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

function Ensure-ContestTools {
    Write-Host ""
    Write-Host ">>> Contest tools (aws / kubectl / docker / bash)" -ForegroundColor Cyan

    $pf = ${env:ProgramFiles}
    $pf86 = ${env:ProgramFiles(x86)}
    $local = $env:LOCALAPPDATA

    $aws = Find-ToolPath -Name "aws" -CandidateExes @(
        (Join-Path $pf "Amazon\AWSCLIV2\aws.exe")
        (Join-Path $pf86 "Amazon\AWSCLIV2\aws.exe")
    )
    $kubectl = Find-ToolPath -Name "kubectl" -CandidateExes @(
        (Join-Path $pf "Docker\Docker\resources\bin\kubectl.exe")
        (Join-Path $local "Microsoft\WinGet\Links\kubectl.exe")
        (Join-Path $pf "Kubernetes\Minikube\kubectl.exe")
    )
    $docker = Find-ToolPath -Name "docker" -CandidateExes @(
        (Join-Path $pf "Docker\Docker\resources\bin\docker.exe")
        (Join-Path $env:ProgramData "DockerDesktop\version-bin\docker.exe")
    )
    $bash = Find-ToolPath -Name "bash" -CandidateExes @(
        (Join-Path $pf "Git\bin\bash.exe")
        (Join-Path $pf "Git\usr\bin\bash.exe")
        (Join-Path $pf86 "Git\bin\bash.exe")
    )

    $missing = @()
    if (-not $aws) { $missing += "AWS CLI v2 (aws.exe) - https://aws.amazon.com/cli/" }
    if (-not $kubectl) { $missing += "kubectl - https://kubernetes.io/docs/tasks/tools/" }
    if (-not $docker) { $missing += "Docker Desktop (docker.exe)" }
    if (-not $bash) { $missing += "Git for Windows (bash.exe) - https://git-scm.com/download/win" }

    if ($missing.Count -gt 0) {
        Write-Host "[!] Missing tools required for day1/002 apply:" -ForegroundColor Red
        foreach ($m in $missing) {
            Write-Host ("    - {0}" -f $m) -ForegroundColor Yellow
        }
        Write-Host "Install them, open a NEW PowerShell, then re-run .\start.cmd" -ForegroundColor Yellow
        throw "Contest tools missing"
    }

    Add-PathDir (Split-Path -Parent $aws)
    Add-PathDir (Split-Path -Parent $kubectl)
    Add-PathDir (Split-Path -Parent $docker)
    Add-PathDir (Split-Path -Parent $bash)

    # Prefer Git\bin so `bash` resolves without /bin/bash
    $gitBin = Join-Path $pf "Git\bin"
    if (Test-Path -LiteralPath $gitBin) { Add-PathDir $gitBin }

    Write-Host ("[OK] aws={0}" -f $aws) -ForegroundColor Green
    Write-Host ("[OK] kubectl={0}" -f $kubectl) -ForegroundColor Green
    Write-Host ("[OK] docker={0}" -f $docker) -ForegroundColor Green
    Write-Host ("[OK] bash={0}" -f $bash) -ForegroundColor Green

    & aws --version
    if ($LASTEXITCODE -ne 0) { throw "aws --version failed" }
    & kubectl version --client --output=yaml 2>$null | Select-Object -First 1 | Out-Null
    & docker version --format "{{.Client.Version}}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] docker daemon may be stopped - start Docker Desktop before apply" -ForegroundColor Yellow
    }
    & bash -lc "echo bash-ok" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bash smoke failed" }
}
