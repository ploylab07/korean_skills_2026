# Ensure contest binaries on PATH for Windows apply.
# Auto-installs aws (MSI/winget), Git (winget), kubectl (download to build\.bin).
# Docker Desktop cannot be fully automated - user must install + start it.
# Encoding: UTF-8 with BOM (Windows PowerShell 5.x)

$script:ContestToolsBinDir = Join-Path $PSScriptRoot ".bin"

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

function Publish-TerraformBinDir {
    param(
        [string]$AwsPath,
        [string]$KubectlPath
    )
    New-Item -ItemType Directory -Force -Path $script:ContestToolsBinDir | Out-Null

    if ($AwsPath -and (Test-Path -LiteralPath $AwsPath)) {
        $dest = Join-Path $script:ContestToolsBinDir "aws.exe"
        if (-not (Test-Path -LiteralPath $dest)) {
            try {
                New-Item -ItemType HardLink -Path $dest -Target $AwsPath -Force -ErrorAction Stop | Out-Null
            }
            catch {
                Copy-Item -LiteralPath $AwsPath -Destination $dest -Force
            }
        }
    }
    if ($KubectlPath -and (Test-Path -LiteralPath $KubectlPath)) {
        $dest = Join-Path $script:ContestToolsBinDir "kubectl.exe"
        if (-not (Test-Path -LiteralPath $dest)) {
            try {
                New-Item -ItemType HardLink -Path $dest -Target $KubectlPath -Force -ErrorAction Stop | Out-Null
            }
            catch {
                Copy-Item -LiteralPath $KubectlPath -Destination $dest -Force
            }
        }
    }
    Add-PathDir $script:ContestToolsBinDir
}

    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$machine;$user"
    Add-PathDir $script:ContestToolsBinDir
}

function Test-NeedsBashLocalExec([string]$RelPath) {
    return ($RelPath -match '(?i)day1\\(002|007)|day2\\(002|007|008)')
}

function Test-NeedsKubectl([string]$RelPath) {
    return ($RelPath -match '(?i)day1\\(002|007)|day2\\(007|008)')
}

function Test-NeedsDocker([string]$RelPath) {
    # Image builds use CodeBuild (build/modules/ecr-codebuild) — local Docker not required
    return $false
}

function Install-KubectlPortable {
    New-Item -ItemType Directory -Force -Path $script:ContestToolsBinDir | Out-Null
    $dest = Join-Path $script:ContestToolsBinDir "kubectl.exe"
    if (Test-Path -LiteralPath $dest) { return $dest }
    $verUrl = "https://dl.k8s.io/release/stable.txt"
    Write-Host "Downloading kubectl to build\.bin ..." -ForegroundColor Yellow
    $ver = (Invoke-WebRequest -Uri $verUrl -UseBasicParsing).Content.Trim()
    $url = "https://dl.k8s.io/release/$ver/bin/windows/amd64/kubectl.exe"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    return $dest
}

function Install-AwsCliMsi {
    $msi = Join-Path ([System.IO.Path]::GetTempPath()) "AWSCLIV2.msi"
    Write-Host "Downloading AWS CLI v2 MSI ..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi -UseBasicParsing
    Write-Host "Installing AWS CLI v2 (quiet) ..." -ForegroundColor Yellow
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", $msi, "/qn", "/norestart") -Wait -PassThru
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw ("AWS CLI MSI install failed (exit {0})" -f $p.ExitCode)
    }
}

function Install-WithWinget([string]$Id, [string]$Label) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }
    Write-Host ("Installing {0} via winget ({1}) ..." -f $Label, $Id) -ForegroundColor Yellow
    & winget install --id $Id -e --accept-package-agreements --accept-source-agreements --disable-interactivity
    return ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) # already installed
}

function Try-InstallMissingTools {
    param(
        [bool]$NeedAws,
        [bool]$NeedKubectl,
        [bool]$NeedBash,
        [bool]$NeedDocker
    )
    Write-Host ""
    Write-Host "Auto-install missing tools? (kubectl download / AWS MSI / Git winget)" -ForegroundColor Cyan
    Write-Host "Docker Desktop still needs a manual install if missing." -ForegroundColor Yellow
    $ans = Read-Host "Install now? [Y/n]"
    if ($ans -match '^[Nn]') { return }

    if ($NeedKubectl) {
        try { $null = Install-KubectlPortable } catch { Write-Host ("kubectl download failed: {0}" -f $_) -ForegroundColor Red }
    }
    if ($NeedAws) {
        $ok = $false
        try { $ok = Install-WithWinget -Id "Amazon.AWSCLI" -Label "AWS CLI" } catch { $ok = $false }
        if (-not $ok) {
            try { Install-AwsCliMsi } catch { Write-Host ("AWS CLI install failed: {0}" -f $_) -ForegroundColor Red }
        }
    }
    if ($NeedBash) {
        $ok = $false
        try { $ok = Install-WithWinget -Id "Git.Git" -Label "Git for Windows" } catch { $ok = $false }
        if (-not $ok) {
            Write-Host "Git winget failed. Install from https://git-scm.com/download/win" -ForegroundColor Yellow
        }
    }
    if ($NeedDocker) {
        $ok = $false
        try { $ok = Install-WithWinget -Id "Docker.DockerDesktop" -Label "Docker Desktop" } catch { $ok = $false }
        if ($ok) {
            Write-Host "Docker Desktop install started/queued. Start Docker Desktop, wait until it is running, then re-run .\start.cmd" -ForegroundColor Yellow
        }
        else {
            Write-Host "Install Docker Desktop manually: https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
        }
    }

    Refresh-ProcessPath
}

function Resolve-ContestTools {
    param([string]$RelPath)

    $pf = ${env:ProgramFiles}
    $pf86 = ${env:ProgramFiles(x86)}
    $local = $env:LOCALAPPDATA
    Add-PathDir $script:ContestToolsBinDir

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
            (Join-Path $script:ContestToolsBinDir "kubectl.exe")
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

    return @{
        NeedBash    = $needBash
        NeedKubectl = $needKubectl
        NeedDocker  = $needDocker
        Aws         = $aws
        Kubectl     = $kubectl
        Docker      = $docker
        Bash        = $bash
    }
}

function Test-DockerDaemon {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $null = & docker info 1>$null 2>$null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($null -eq $code) { $code = 1 }
    return ([int]$code -eq 0)
}

function Start-DockerDesktopAndWait {
    param([int]$TimeoutSec = 180)

    if (Test-DockerDaemon) { return $true }

    $desktop = @(
        (Join-Path ${env:ProgramFiles} "Docker\Docker\Docker Desktop.exe")
        (Join-Path $env:LOCALAPPDATA "Docker\Docker Desktop.exe")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

    if (-not $desktop) {
        Write-Host "[!] Docker Desktop.exe not found" -ForegroundColor Red
        return $false
    }

    $running = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if (-not $running) {
        Write-Host ("Starting Docker Desktop: {0}" -f $desktop) -ForegroundColor Yellow
        Start-Process -FilePath $desktop | Out-Null
    }
    else {
        Write-Host "Docker Desktop process is up; waiting for engine..." -ForegroundColor Yellow
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $n = 0
    while ((Get-Date) -lt $deadline) {
        $n++
        if (Test-DockerDaemon) {
            Write-Host "[OK] Docker engine is ready" -ForegroundColor Green
            return $true
        }
        if (($n % 6) -eq 0) {
            $elapsed = [int]((Get-Date) - ($deadline.AddSeconds(-$TimeoutSec))).TotalSeconds
            Write-Host ("  still waiting for docker engine... ({0}s / {1}s)" -f $elapsed, $TimeoutSec) -ForegroundColor DarkYellow
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Ensure-ContestTools {
    param(
        [string]$RelPath = ""
    )
    Write-Host ""
    Write-Host ">>> Contest tools check ($RelPath)" -ForegroundColor Cyan
    Refresh-ProcessPath

    $t = Resolve-ContestTools -RelPath $RelPath
    $missing = @()
    if (-not $t.Aws) { $missing += "AWS CLI v2 (aws.exe)" }
    if ($t.NeedKubectl -and -not $t.Kubectl) { $missing += "kubectl" }
    if ($t.NeedDocker -and -not $t.Docker) { $missing += "Docker Desktop (docker.exe)" }
    if ($t.NeedBash -and -not $t.Bash) { $missing += "Git for Windows (bash.exe)" }

    if ($missing.Count -gt 0) {
        Write-Host "[!] Missing tools:" -ForegroundColor Yellow
        foreach ($m in $missing) { Write-Host ("    - {0}" -f $m) -ForegroundColor Yellow }
        Try-InstallMissingTools -NeedAws (-not $t.Aws) -NeedKubectl ($t.NeedKubectl -and -not $t.Kubectl) `
            -NeedBash ($t.NeedBash -and -not $t.Bash) -NeedDocker ($t.NeedDocker -and -not $t.Docker)
        Refresh-ProcessPath
        $t = Resolve-ContestTools -RelPath $RelPath
    }

    $still = @()
    if (-not $t.Aws) { $still += "AWS CLI v2 - https://aws.amazon.com/cli/" }
    if ($t.NeedKubectl -and -not $t.Kubectl) { $still += "kubectl - will retry download on next run" }
    if ($t.NeedDocker -and -not $t.Docker) {
        $still += "Docker Desktop - install + START it, then re-run .\start.cmd (https://www.docker.com/products/docker-desktop/)"
    }
    if ($t.NeedBash -and -not $t.Bash) { $still += "Git for Windows - https://git-scm.com/download/win" }

    if ($still.Count -gt 0) {
        Write-Host "[!] Still missing after install attempt:" -ForegroundColor Red
        foreach ($m in $still) { Write-Host ("    - {0}" -f $m) -ForegroundColor Yellow }
        Write-Host "Open a NEW PowerShell after MSI/winget installs, then re-run .\start.cmd" -ForegroundColor Yellow
        throw "Contest tools missing"
    }

    Add-PathDir (Split-Path -Parent $t.Aws)
    if ($t.Kubectl) { Add-PathDir (Split-Path -Parent $t.Kubectl) }
    if ($t.Docker) { Add-PathDir (Split-Path -Parent $t.Docker) }
    if ($t.Bash) {
        Add-PathDir (Split-Path -Parent $t.Bash)
        $gitBin = Join-Path ${env:ProgramFiles} "Git\bin"
        if (Test-Path -LiteralPath $gitBin) { Add-PathDir $gitBin }
    }

    Publish-TerraformBinDir -AwsPath $t.Aws -KubectlPath $t.Kubectl

    Write-Host ("[OK] aws={0}" -f $t.Aws) -ForegroundColor Green
    if ($t.NeedKubectl) { Write-Host ("[OK] kubectl={0}" -f $t.Kubectl) -ForegroundColor Green }
    if ($t.NeedDocker) { Write-Host ("[OK] docker={0}" -f $t.Docker) -ForegroundColor Green }
    if ($t.NeedBash) { Write-Host ("[OK] bash={0}" -f $t.Bash) -ForegroundColor Green }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & aws --version
    $awsCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($awsCode -ne 0) { throw "aws --version failed" }

    if ($t.NeedBash) {
        $ErrorActionPreference = "Continue"
        & bash -lc "echo bash-ok" 1>$null 2>$null
        $bashCode = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        if ($bashCode -ne 0) { throw "bash smoke failed" }
    }
    if ($t.NeedDocker) {
        if (-not (Start-DockerDesktopAndWait -TimeoutSec 180)) {
            Write-Host "[!] Docker engine not ready (npipe docker_engine missing)." -ForegroundColor Red
            Write-Host "    1) Start 'Docker Desktop' from Start Menu" -ForegroundColor Yellow
            Write-Host "    2) Wait until status is Running (whale icon steady)" -ForegroundColor Yellow
            Write-Host "    3) Re-run .\start.cmd" -ForegroundColor Yellow
            throw "Docker Desktop is not running"
        }
    }
}
