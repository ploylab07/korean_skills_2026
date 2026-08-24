# Shared helpers for day3 Windows scripts.
# Encoding: UTF-8 with BOM (Windows PowerShell 5.x)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Script:TfDir = Join-Path $Script:Root "terraform"
$Script:EdgeDir = Join-Path $Script:Root "edge"
$Script:K8sDir = Join-Path $Script:Root "k8s"
$Script:RepoRoot = (Resolve-Path (Join-Path $Script:Root "..")).Path

function Resolve-RepoTerraform {
    $cmd = Join-Path $Script:RepoRoot "terraform.cmd"
    if (Test-Path -LiteralPath $cmd) { return $cmd }
    $exe = Join-Path $Script:RepoRoot "build\.bin\terraform.exe"
    if (Test-Path -LiteralPath $exe) { return $exe }
    if (Get-Command terraform -ErrorAction SilentlyContinue) { return "terraform" }
    Fail "terraform not found. Run .\\start.cmd or .\\terraform.cmd from repo root first."
}

function Import-Day3Env {
    $loadEnv = Join-Path $Script:RepoRoot "build\load-env.ps1"
    if (Test-Path -LiteralPath $loadEnv) {
        . $loadEnv
        Import-RepoEnv -BuildDir (Join-Path $Script:RepoRoot "build")
    }
    $mirror = Join-Path $Script:RepoRoot "build\ensure-tf-mirror.ps1"
    if (Test-Path -LiteralPath $mirror) {
        . $mirror
    }
}

Import-Day3Env
$Script:TfBin = Resolve-RepoTerraform

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Cyan
}

function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)
    throw $Message
}

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Fail "Required command not found in PATH: $Name"
    }
}

function Assert-NativeSuccess {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    if ($LASTEXITCODE -ne 0) {
        Fail "$CommandName failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Tf {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & $Script:TfBin "-chdir=$Script:TfDir" @Arguments
    Assert-NativeSuccess "terraform"
}

function Invoke-EdgeTf {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & $Script:TfBin "-chdir=$Script:EdgeDir" @Arguments
    Assert-NativeSuccess "terraform(edge)"
}

function Get-TfOutputRaw {
    param([Parameter(Mandatory = $true)][string]$Name)
    $value = & $Script:TfBin "-chdir=$Script:TfDir" output -raw $Name
    Assert-NativeSuccess "terraform output $Name"
    return (($value | Out-String).Trim())
}

function Get-TfOutputJson {
    param([Parameter(Mandatory = $true)][string]$Name)
    $value = & $Script:TfBin "-chdir=$Script:TfDir" output -json $Name
    Assert-NativeSuccess "terraform output -json $Name"
    return (($value | Out-String).Trim())
}

function Get-AwsRegion {
    try { return Get-TfOutputRaw "aws_region" } catch { return "ap-northeast-2" }
}

function Get-ClusterName { return Get-TfOutputRaw "cluster_name" }
function Get-ProjectName {
    try { return Get-TfOutputRaw "project_name" } catch { return "apdev-dev" }
}

function Ensure-CoreState {
    $state = Join-Path $Script:TfDir "terraform.tfstate"
    if (-not (Test-Path $state)) {
        Fail "Core Terraform state not found: $state"
    }
}

function Ensure-Kubeconfig {
    $region = Get-AwsRegion
    $cluster = Get-ClusterName
    & aws eks update-kubeconfig --region $region --name $cluster | Out-Host
    Assert-NativeSuccess "aws eks update-kubeconfig"
}

function Invoke-Aws {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & aws @Arguments
    Assert-NativeSuccess "aws"
}

function Invoke-Kubectl {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & kubectl @Arguments
    Assert-NativeSuccess "kubectl"
}

function Ensure-Day3Tfvars {
    $tfvars = Join-Path $Script:TfDir "terraform.tfvars"
    $example = Join-Path $Script:TfDir "terraform.tfvars.example"
    if (-not (Test-Path -LiteralPath $tfvars)) {
        if (-not (Test-Path -LiteralPath $example)) {
            Fail "Missing $example"
        }
        Copy-Item -LiteralPath $example -Destination $tfvars
        Write-Host "Created: $tfvars"
    }

    if ($env:DB_PASSWORD -and $env:DB_PASSWORD.Length -ge 8) {
        $env:TF_VAR_db_password = $env:DB_PASSWORD
    }

    $needsPassword = $false
    if (Select-String -Path $tfvars -Pattern 'CHANGE_ME_STRONG_PASSWORD' -Quiet) {
        $needsPassword = $true
    }
    if ($needsPassword -and -not $env:TF_VAR_db_password) {
        $secure = Read-Host "RDS db_password (min 8 chars)" -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
        if ([string]::IsNullOrWhiteSpace($plain) -or $plain.Length -lt 8) {
            Fail "db_password must be at least 8 characters."
        }
        $env:TF_VAR_db_password = $plain
        $env:DB_PASSWORD = $plain
        # Keep placeholder in file; TF_VAR overrides so password is not written to disk.
        Write-Host "Using TF_VAR_db_password (not written to terraform.tfvars)."
    }
}
