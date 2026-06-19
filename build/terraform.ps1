# Portable Terraform wrapper for Windows (PowerShell)
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
    Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $BinDir -Force
    Remove-Item $tmpZip -Force
    Write-Host "Terraform installed: $TfExe"
}

Ensure-Terraform

. (Join-Path $ScriptDir "load-env.ps1")
Import-RepoEnv -BuildDir $ScriptDir

$RepoRoot = Split-Path -Parent $ScriptDir
$EnvFile = Join-Path $RepoRoot ".env"
if (-not (Test-Path $EnvFile) -and ($args.Count -gt 0) -and ($args[0] -in @("apply", "plan"))) {
    Write-Host "hint: AWS 키가 없으면 먼저 setup-aws 를 실행하세요." -ForegroundColor Yellow
    Write-Host "      .\setup-aws.cmd" -ForegroundColor Yellow
}

& $TfExe @args
exit $LASTEXITCODE
