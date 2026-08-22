# Ensure contest binaries on PATH for Windows apply.
# Auto-installs aws (MSI/winget), Git (winget), kubectl (download to build\.bin).
# Docker Desktop cannot be fully automated - user must install + start it.
# Encoding: UTF-8 with BOM (Windows PowerShell 5.x)

$script:ContestToolsBinDir = Join-Path $PSScriptRoot ".bin"

function Get-WebText {
    param([Parameter(Mandatory = $true)][string]$Uri)
    $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing
    $content = $resp.Content
    if ($content -is [byte[]]) {
        return ([System.Text.Encoding]::UTF8.GetString($content)).Trim()
    }
    return ("$content").Trim()
}

function Invoke-WebFile {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

function Find-ExeUnder {
    param(
        [string[]]$Roots,
        [Parameter(Mandatory = $true)][string]$ExeName,
        [int]$MaxDepth = 8
    )
    foreach ($root in $Roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        try {
            $gciParams = @{
                LiteralPath = $root
                Filter      = $ExeName
                Recurse     = $true
                ErrorAction = 'SilentlyContinue'
            }
            # -Depth is PS 5.0+; omit on older hosts
            if ((Get-Command Get-ChildItem).Parameters.ContainsKey('Depth')) {
                $gciParams.Depth = $MaxDepth
            }
            $hit = Get-ChildItem @gciParams | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
        catch { }
    }
    return $null
}

function Find-ToolPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$CandidateExes,
        [string[]]$SearchRoots = @(),
        [string]$ExeName = ""
    )
    if (-not $ExeName) { $ExeName = "$Name.exe" }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }
    foreach ($p in $CandidateExes) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            return $p
        }
    }
    if ($SearchRoots.Count -gt 0) {
        return Find-ExeUnder -Roots $SearchRoots -ExeName $ExeName
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

    # AWS CLI v2 is not a standalone exe. Copying/hardlinking aws.exe into build\.bin
    # makes kubernetes/helm exec fail with exit 4294967295 (-1).
    $stub = Join-Path $script:ContestToolsBinDir "aws.exe"
    if (Test-Path -LiteralPath $stub) {
        Remove-Item -LiteralPath $stub -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] removed broken build\.bin\aws.exe stub" -ForegroundColor Yellow
    }
    if ($AwsPath -and (Test-Path -LiteralPath $AwsPath)) {
        Add-PathDir (Split-Path -Parent $AwsPath)
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
    # AWS CLI dir must win over build\.bin (no stub aws.exe there)
    if ($AwsPath -and (Test-Path -LiteralPath $AwsPath)) {
        Add-PathDir (Split-Path -Parent $AwsPath)
    }
}

function Refresh-ProcessPath {
    try {
        $sig = @'
using System;
using System.Runtime.InteropServices;
public static class ContestToolsNative {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lResult);
}
'@
        Add-Type -TypeDefinition $sig -ErrorAction SilentlyContinue | Out-Null
        [UIntPtr]$ignore = [UIntPtr]::Zero
        [ContestToolsNative]::SendMessageTimeout(
            [IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$ignore) | Out-Null
    }
    catch { }

    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$machine;$user"
    Add-PathDir $script:ContestToolsBinDir
}

function Test-ContestToolsReady {
    param([hashtable]$Tools)
    if (-not $Tools.Aws) { return $false }
    if ($Tools.NeedKubectl -and -not $Tools.Kubectl) { return $false }
    if ($Tools.NeedHelm -and -not $Tools.Helm) { return $false }
    if ($Tools.NeedDocker -and -not $Tools.Docker) { return $false }
    if ($Tools.NeedBash -and -not $Tools.Bash) { return $false }
    return $true
}

function Wait-ForContestTools {
    param(
        [Parameter(Mandatory = $true)][string]$RelPath,
        [int]$TimeoutSec = 60
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Refresh-ProcessPath
        $t = Resolve-ContestTools -RelPath $RelPath
        if (Test-ContestToolsReady -Tools $t) { return $t }
        Start-Sleep -Seconds 2
    }
    Refresh-ProcessPath
    return (Resolve-ContestTools -RelPath $RelPath)
}

function Test-NeedsBashLocalExec([string]$RelPath) {
    return ($RelPath -match '(?i)day1\\(002|003|007)|day2\\(002|007|008)')
}

function Test-NeedsKubectl([string]$RelPath) {
    return ($RelPath -match '(?i)day1\\(002|003|007)|day2\\(007|008)')
}

function Test-NeedsHelm([string]$RelPath) {
    return ($RelPath -match '(?i)day1\\(002|003|007)')
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
    $ver = Get-WebText -Uri $verUrl
    $url = "https://dl.k8s.io/release/$ver/bin/windows/amd64/kubectl.exe"
    Invoke-WebFile -Uri $url -OutFile $dest
    return $dest
}

function Install-HelmPortable {
    New-Item -ItemType Directory -Force -Path $script:ContestToolsBinDir | Out-Null
    $dest = Join-Path $script:ContestToolsBinDir "helm.exe"
    if (Test-Path -LiteralPath $dest) { return $dest }
    Write-Host "Downloading helm to build\.bin ..." -ForegroundColor Yellow
    $ver = Get-WebText -Uri "https://get.helm.sh/helm-latest-version"
    $zip = Join-Path ([System.IO.Path]::GetTempPath()) ("helm-{0}-windows-amd64.zip" -f $ver)
    $url = "https://get.helm.sh/helm-$ver-windows-amd64.zip"
    Invoke-WebFile -Uri $url -OutFile $zip
    $extract = Join-Path ([System.IO.Path]::GetTempPath()) ("helm-extract-{0}" -f [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    try {
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $exe = Get-ChildItem -LiteralPath $extract -Filter "helm.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $exe) { throw "helm.exe not found in downloaded archive" }
        Copy-Item -LiteralPath $exe.FullName -Destination $dest -Force
    }
    finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $dest
}

function Install-AwsCliMsi {
    $msi = Join-Path ([System.IO.Path]::GetTempPath()) "AWSCLIV2.msi"
    Write-Host "Downloading AWS CLI v2 MSI ..." -ForegroundColor Yellow
    Invoke-WebFile -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi
    Write-Host "Installing AWS CLI v2 (quiet) ..." -ForegroundColor Yellow
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", $msi, "/qn", "/norestart") -Wait -PassThru
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw ("AWS CLI MSI install failed (exit {0})" -f $p.ExitCode)
    }
    $awsExe = Join-Path ${env:ProgramFiles} "Amazon\AWSCLIV2\aws.exe"
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $awsExe) { return $awsExe }
        Start-Sleep -Seconds 2
    }
    throw "AWS CLI MSI finished but aws.exe not found"
}

function Install-GitSilent {
    Write-Host "Downloading Git for Windows (silent) ..." -ForegroundColor Yellow
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) "Git-64-bit.exe"
    $url = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe"
    Invoke-WebFile -Uri $url -OutFile $installer
    Write-Host "Installing Git for Windows (quiet) ..." -ForegroundColor Yellow
    $p = Start-Process -FilePath $installer -ArgumentList @(
        "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS",
        "/RESTARTAPPLICATIONS", "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh"
    ) -Wait -PassThru
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) {
        throw ("Git install failed (exit {0})" -f $p.ExitCode)
    }
    $bashExe = Join-Path ${env:ProgramFiles} "Git\bin\bash.exe"
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $bashExe) { return $bashExe }
        Start-Sleep -Seconds 2
    }
    throw "Git install finished but bash.exe not found"
}

function Install-WithWinget([string]$Id, [string]$Label) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }
    Write-Host ("Installing {0} via winget ({1}) ..." -f $Label, $Id) -ForegroundColor Yellow
    $scopeArgs = @()
    $isAdmin = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal $id
        $isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { }
    if ($isAdmin) { $scopeArgs = @("--scope", "machine") }
    & winget install --id $Id -e @scopeArgs --accept-package-agreements --accept-source-agreements --disable-interactivity
    return ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) # already installed
}

function Try-InstallMissingTools {
    param(
        [bool]$NeedAws,
        [bool]$NeedKubectl,
        [bool]$NeedHelm,
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
            try { $null = Install-AwsCliMsi } catch { Write-Host ("AWS CLI install failed: {0}" -f $_) -ForegroundColor Red }
        }
    }
    if ($NeedBash) {
        $ok = $false
        try { $ok = Install-WithWinget -Id "Git.Git" -Label "Git for Windows" } catch { $ok = $false }
        if (-not $ok) {
            try { $null = Install-GitSilent } catch {
                Write-Host ("Git install failed: {0}" -f $_) -ForegroundColor Red
                Write-Host "Install manually: https://git-scm.com/download/win" -ForegroundColor Yellow
            }
        }
    }
    if ($NeedHelm) {
        $ok = $false
        try { $ok = Install-WithWinget -Id "Helm.Helm" -Label "Helm" } catch { $ok = $false }
        if (-not $ok) {
            try { $null = Install-HelmPortable; $ok = $true } catch {
                Write-Host ("Helm install failed: {0}" -f $_) -ForegroundColor Red
            }
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

    $programSearchRoots = @(
        $pf
        $pf86
        (Join-Path $local "Programs")
        (Join-Path $local "Microsoft\WinGet\Links")
        (Join-Path $local "Microsoft\WinGet\Packages")
        (Join-Path $pf "Amazon")
        (Join-Path $pf "Git")
        (Join-Path $pf "Helm")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $awsSearchRoots = @(
        (Join-Path $pf "Amazon")
        (Join-Path $pf86 "Amazon")
        (Join-Path $local "Programs\Amazon")
        (Join-Path $local "Microsoft\WinGet\Packages")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $needBash = Test-NeedsBashLocalExec $RelPath
    $needKubectl = Test-NeedsKubectl $RelPath
    $needHelm = Test-NeedsHelm $RelPath
    $needDocker = Test-NeedsDocker $RelPath

    $aws = Find-ToolPath -Name "aws" -CandidateExes @(
        (Join-Path $pf "Amazon\AWSCLIV2\aws.exe")
        (Join-Path $pf86 "Amazon\AWSCLIV2\aws.exe")
        (Join-Path $local "Programs\Amazon\AWSCLIV2\aws.exe")
    ) -SearchRoots $awsSearchRoots -ExeName "aws.exe"
    $kubectl = $null
    $helm = $null
    $docker = $null
    $bash = $null
    if ($needKubectl) {
        $kubectl = Find-ToolPath -Name "kubectl" -CandidateExes @(
            (Join-Path $script:ContestToolsBinDir "kubectl.exe")
            (Join-Path $pf "Docker\Docker\resources\bin\kubectl.exe")
            (Join-Path $local "Microsoft\WinGet\Links\kubectl.exe")
        )
    }
    if ($needHelm) {
        $helm = Find-ToolPath -Name "helm" -CandidateExes @(
            (Join-Path $script:ContestToolsBinDir "helm.exe")
            (Join-Path $pf "Helm\helm.exe")
            (Join-Path $pf86 "Helm\helm.exe")
            (Join-Path $local "Programs\Helm\helm.exe")
            (Join-Path $local "Microsoft\WinGet\Links\helm.exe")
        ) -SearchRoots $programSearchRoots -ExeName "helm.exe"
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
            (Join-Path $local "Programs\Git\bin\bash.exe")
            (Join-Path $local "Programs\Git\usr\bin\bash.exe")
        ) -SearchRoots @(
            (Join-Path $pf "Git")
            (Join-Path $local "Programs\Git")
        ) -ExeName "bash.exe"
    }

    return @{
        NeedBash    = $needBash
        NeedKubectl = $needKubectl
        NeedHelm    = $needHelm
        NeedDocker  = $needDocker
        Aws         = $aws
        Kubectl     = $kubectl
        Helm        = $helm
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
    if ($t.NeedHelm -and -not $t.Helm) { $missing += "Helm (helm.exe)" }
    if ($t.NeedDocker -and -not $t.Docker) { $missing += "Docker Desktop (docker.exe)" }
    if ($t.NeedBash -and -not $t.Bash) { $missing += "Git for Windows (bash.exe)" }

    if ($missing.Count -gt 0) {
        Write-Host "[!] Missing tools:" -ForegroundColor Yellow
        foreach ($m in $missing) { Write-Host ("    - {0}" -f $m) -ForegroundColor Yellow }
        Try-InstallMissingTools -NeedAws (-not $t.Aws) -NeedKubectl ($t.NeedKubectl -and -not $t.Kubectl) `
            -NeedHelm ($t.NeedHelm -and -not $t.Helm) -NeedBash ($t.NeedBash -and -not $t.Bash) -NeedDocker ($t.NeedDocker -and -not $t.Docker)
        Write-Host "Waiting for installers to finish (up to 60s) ..." -ForegroundColor Cyan
        $t = Wait-ForContestTools -RelPath $RelPath -TimeoutSec 60
    }

    $still = @()
    if (-not $t.Aws) { $still += "AWS CLI v2 - https://aws.amazon.com/cli/" }
    if ($t.NeedKubectl -and -not $t.Kubectl) { $still += "kubectl - will retry download on next run" }
    if ($t.NeedHelm -and -not $t.Helm) { $still += "Helm - https://helm.sh/docs/intro/install/" }
    if ($t.NeedDocker -and -not $t.Docker) {
        $still += "Docker Desktop - install + START it, then re-run .\start.cmd (https://www.docker.com/products/docker-desktop/)"
    }
    if ($t.NeedBash -and -not $t.Bash) { $still += "Git for Windows - https://git-scm.com/download/win" }

    if ($still.Count -gt 0) {
        Write-Host "[!] Still missing after install attempt:" -ForegroundColor Red
        foreach ($m in $still) { Write-Host ("    - {0}" -f $m) -ForegroundColor Yellow }
        Write-Host "Retrying portable downloads (kubectl/helm) and AWS MSI / Git silent where possible ..." -ForegroundColor Cyan
        if (-not $t.Aws) {
            try {
                $ok = $false
                try { $ok = Install-WithWinget -Id "Amazon.AWSCLI" -Label "AWS CLI" } catch { $ok = $false }
                if (-not $ok) { $null = Install-AwsCliMsi }
            }
            catch { Write-Host ("AWS retry failed: {0}" -f $_) -ForegroundColor Red }
        }
        if ($t.NeedBash -and -not $t.Bash) {
            try {
                $ok = $false
                try { $ok = Install-WithWinget -Id "Git.Git" -Label "Git for Windows" } catch { $ok = $false }
                if (-not $ok) { $null = Install-GitSilent }
            }
            catch { Write-Host ("Git retry failed: {0}" -f $_) -ForegroundColor Red }
        }
        if ($t.NeedKubectl -and -not $t.Kubectl) {
            try { $null = Install-KubectlPortable }
            catch { Write-Host ("kubectl retry failed: {0}" -f $_) -ForegroundColor Red }
        }
        if ($t.NeedHelm -and -not $t.Helm) {
            try { $null = Install-HelmPortable }
            catch { Write-Host ("Helm retry failed: {0}" -f $_) -ForegroundColor Red }
        }
        Refresh-ProcessPath
        $t = Resolve-ContestTools -RelPath $RelPath

        $still = @()
        if (-not $t.Aws) { $still += "AWS CLI v2 - https://aws.amazon.com/cli/" }
        if ($t.NeedKubectl -and -not $t.Kubectl) { $still += "kubectl - will retry download on next run" }
        if ($t.NeedHelm -and -not $t.Helm) { $still += "Helm - https://helm.sh/docs/intro/install/" }
        if ($t.NeedDocker -and -not $t.Docker) {
            $still += "Docker Desktop - install + START it, then re-run .\start.cmd (https://www.docker.com/products/docker-desktop/)"
        }
        if ($t.NeedBash -and -not $t.Bash) { $still += "Git for Windows - https://git-scm.com/download/win" }
    }

    if ($still.Count -gt 0) {
        Write-Host "[!] Still missing after install attempt:" -ForegroundColor Red
        foreach ($m in $still) { Write-Host ("    - {0}" -f $m) -ForegroundColor Yellow }
        Write-Host "Manual fix (Admin PowerShell):" -ForegroundColor Yellow
        Write-Host "  winget install -e --id Amazon.AWSCLI Git.Git Helm.Helm --accept-package-agreements" -ForegroundColor Yellow
        Write-Host "Or open a NEW PowerShell after MSI/winget installs, then re-run .\start.cmd" -ForegroundColor Yellow
        throw "Contest tools missing"
    }

    Add-PathDir (Split-Path -Parent $t.Aws)
    if ($t.Kubectl) { Add-PathDir (Split-Path -Parent $t.Kubectl) }
    if ($t.Helm) { Add-PathDir (Split-Path -Parent $t.Helm) }
    if ($t.Docker) { Add-PathDir (Split-Path -Parent $t.Docker) }
    if ($t.Bash) {
        Add-PathDir (Split-Path -Parent $t.Bash)
        $gitBin = Join-Path ${env:ProgramFiles} "Git\bin"
        if (Test-Path -LiteralPath $gitBin) { Add-PathDir $gitBin }
    }

    Publish-TerraformBinDir -AwsPath $t.Aws -KubectlPath $t.Kubectl
    Add-PathDir (Split-Path -Parent $t.Aws)

    Write-Host ("[OK] aws={0}" -f $t.Aws) -ForegroundColor Green
    if ($t.NeedKubectl) { Write-Host ("[OK] kubectl={0}" -f $t.Kubectl) -ForegroundColor Green }
    if ($t.NeedHelm) { Write-Host ("[OK] helm={0}" -f $t.Helm) -ForegroundColor Green }
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
