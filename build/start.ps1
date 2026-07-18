# 대회용 Windows 원클릭 — .\start.cmd
# 1) PowerShell/인터넷 확인  2) Terraform 설치  3) .env  4) 과제 선택  5) apply
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
    Write-Step "1/5 PowerShell / 인터넷 확인"

    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5) {
        throw "PowerShell 5.0 이상이 필요합니다. 현재: $psVer"
    }
    Write-Ok "PowerShell $psVer"

    try {
        $null = Invoke-WebRequest -Uri "https://releases.hashicorp.com" -Method Head -UseBasicParsing -TimeoutSec 10
        Write-Ok "인터넷 연결 OK"
    }
    catch {
        throw "인터넷 연결이 필요합니다 (Terraform 다운로드)."
    }
}

function Ensure-TerraformBinary {
    Write-Step "2/5 Terraform 확인/설치"
    if (-not (Test-Path $TfCmd)) {
        throw "terraform.cmd 가 없습니다: $TfCmd"
    }
    & $TfCmd version
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform 실행 실패"
    }
    Write-Ok "Terraform 준비됨"
}

function Ensure-AwsEnv {
    Write-Step "3/5 AWS .env 설정"

    if (Test-Path $EnvFile) {
        . (Join-Path $BuildDir "load-env.ps1")
        Import-RepoEnv -BuildDir $BuildDir
        if ($env:AWS_ACCESS_KEY_ID -and $env:AWS_SECRET_ACCESS_KEY) {
            Write-Ok ".env 있음 (region=$($env:AWS_DEFAULT_REGION))"
            $ans = Read-Host "다시 입력할까요? [y/N]"
            if ($ans -notmatch '^[Yy]') {
                return
            }
        }
    }

    Write-Host "AWS Access Key / Secret / Region 을 입력하세요." -ForegroundColor Yellow
    & (Join-Path $BuildDir "setup-aws.ps1")
    . (Join-Path $BuildDir "load-env.ps1")
    Import-RepoEnv -BuildDir $BuildDir
    if (-not ($env:AWS_ACCESS_KEY_ID -and $env:AWS_SECRET_ACCESS_KEY)) {
        throw ".env 설정 실패"
    }
    Write-Ok ".env 저장 완료"
}

function Resolve-AssignmentPath([string]$RelPath) {
    $full = Join-Path $Root $RelPath
    if (-not (Test-Path $full)) {
        throw "과제 폴더가 없습니다: $RelPath"
    }
    $tf = Get-ChildItem -Path $full -Filter "*.tf" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.terraform\\' }
    if (-not $tf) {
        throw "Terraform(.tf) 파일이 없습니다: $RelPath"
    }
    return (Resolve-Path $full).Path
}

function Prompt-Folder {
    Write-Step "4/5 과제 선택"
    Write-Host "=== 과제 목록 ===" -ForegroundColor Cyan
    foreach ($item in $Catalog) {
        $exists = Test-Path (Join-Path $Root $item.Path)
        Write-Host ("  [{0}] {1}{2}" -f $item.Id, $item.Label, $(if ($exists) { "" } else { "  (폴더 없음)" }))
    }
    Write-Host "  [0] 종료"

    while ($true) {
        $choice = Read-Host "번호 선택"
        if ($choice -eq "0") { exit 0 }
        $item = $Catalog | Where-Object { $_.Id -eq $choice } | Select-Object -First 1
        if ($item) { return $item.Path }
        Write-Warn "잘못된 선택입니다."
    }
}

function Invoke-Apply([string]$RelPath) {
    Write-Step "5/5 배포 (apply) — $RelPath"
    $assignPath = Resolve-AssignmentPath $RelPath

    Write-Host "init → validate → plan → apply 순서로 진행합니다." -ForegroundColor Yellow
    $confirm = Read-Host "계속할까요? [Y/n]"
    if ($confirm -match '^[Nn]') {
        Write-Warn "취소됨"
        exit 0
    }

    & $TfCmd -chdir="$assignPath" init "-input=false"
    if ($LASTEXITCODE -ne 0) { throw "terraform init 실패" }

    & $TfCmd -chdir="$assignPath" validate
    if ($LASTEXITCODE -ne 0) { throw "terraform validate 실패" }

    & $TfCmd -chdir="$assignPath" plan "-input=false"
    if ($LASTEXITCODE -ne 0) { throw "terraform plan 실패" }

    & $TfCmd -chdir="$assignPath" apply "-input=false" -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "terraform apply 실패" }

    Write-Ok "배포 완료: $RelPath"
}

# --- main ---
Set-Location $Root
Write-Host "=== Korean Skills 2026 — 대회용 배포 ===" -ForegroundColor Cyan
Write-Host "root: $Root"

Ensure-Prerequisites
Ensure-TerraformBinary
Ensure-AwsEnv
$path = Prompt-Folder
Invoke-Apply -RelPath $path

Write-Host ""
Write-Host "=== 서비스 배포 완료 ===" -ForegroundColor Green
exit 0
