# Portable Terraform wrapper for Windows (PowerShell)
# Encoding: UTF-8 with BOM for Windows PowerShell 5.x
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $ScriptDir ".bin"
$VersionFile = Join-Path $ScriptDir "VERSION"
$TfVersion = (Get-Content $VersionFile -Raw).Trim()
$TfExe = Join-Path $BinDir "terraform.exe"

function Get-PlatformZip {
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch) {
        "AMD64" { $a = "amd64" }
        "ARM64" { $a = "arm64" }
        default { throw "Unsupported architecture: $arch" }
    }
    return "windows_$a"
}

function Ensure-Terraform {
    if (Test-Path $TfExe) { return }

    $platform = Get-PlatformZip
    $zipName = "terraform_${TfVersion}_${platform}.zip"
    $url = "https://releases.hashicorp.com/terraform/${TfVersion}/${zipName}"
    $tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) $zipName

    Write-Host "Downloading Terraform $TfVersion ($platform)..."
    $ok = $false
    foreach ($i in 1..5) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
            $ok = $true
            break
        }
        catch {
            Write-Host "Download failed (attempt $i/5): $_"
            Start-Sleep -Seconds (3 * $i)
        }
    }
    if (-not $ok) { throw "Failed to download Terraform from HashiCorp" }

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $BinDir -Force
    Remove-Item $tmpZip -Force
    Write-Host "Terraform installed: $TfExe"
}

Ensure-Terraform

# Prefer bundled Windows provider mirror (no releases.hashicorp.com provider downloads)
. (Join-Path $ScriptDir "ensure-tf-mirror.ps1")

. (Join-Path $ScriptDir "load-env.ps1")
Import-RepoEnv -BuildDir $ScriptDir

$RepoRoot = Split-Path -Parent $ScriptDir
$EnvFile = Join-Path $RepoRoot ".env"
if (-not (Test-Path $EnvFile) -and ($args.Count -gt 0) -and ($args[0] -in @("apply", "plan"))) {
    Write-Host "hint: set AWS keys with .\setup-aws.cmd first" -ForegroundColor Yellow
}

# Call terraform.exe directly (avoid .cmd arg mangling of -chdir in PowerShell)
& $TfExe @args
exit $LASTEXITCODE
