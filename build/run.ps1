# Single-command harness - verify, hooks, terraform for an assignment folder
# Usage:
#   .\run.cmd                          # smoke verify only
#   .\run.cmd day1                     # verify + init/validate/plan
#   .\run.cmd day1\test-1-2026-06-20   # specific folder
#   .\run.cmd day1 apply               # verify + apply (with -auto-approve)
#   .\run.cmd day1 plan                # verify + plan only
param(
    [Parameter(Position = 0)]
    [string]$AssignmentFolder = "",

    [Parameter(Position = 1)]
    [ValidateSet("", "verify", "init", "validate", "plan", "apply", "destroy", "hooks", "add-rule")]
    [string]$Action = "",

    [string]$RuleName = "",
    [string]$RuleDescription = "",
    [switch]$AlwaysApply,
    [string]$Globs = "",
    [string]$ContentFile = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $Root "build"
$TfCmd = Join-Path $Root "terraform.cmd"
$VerifyCmd = Join-Path $BuildDir "verify.cmd"
$HarnessDir = Join-Path $BuildDir "harness"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ">>> $Message" -ForegroundColor Cyan
}

function Resolve-AssignmentPath([string]$Folder) {
    if ([string]::IsNullOrWhiteSpace($Folder)) {
        return $null
    }
    $candidate = Join-Path $Root $Folder
    if (-not (Test-Path $candidate)) {
        throw "Assignment folder not found: $Folder"
    }
    $tfFiles = Get-ChildItem -Path $candidate -Filter "*.tf" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.terraform\\' }
    if (-not $tfFiles) {
        throw "No .tf files under: $Folder"
    }
    return (Resolve-Path $candidate).Path
}

# Infer action when second positional arg is actually a subfolder
if ($Action -eq "" -and $AssignmentFolder -match '^(init|validate|plan|apply|destroy|verify|hooks|add-rule)$') {
    $Action = $AssignmentFolder
    $AssignmentFolder = ""
}

if ($Action -eq "") {
    if ([string]::IsNullOrWhiteSpace($AssignmentFolder)) {
        $Action = "verify"
    }
    else {
        $Action = "plan"
    }
}

Write-Host "=== Korean Skills 2026 - harness run ==="
Write-Host "root: $Root"
Write-Host "action: $Action"
if ($AssignmentFolder) { Write-Host "folder: $AssignmentFolder" }

# Always ensure Windows hooks are configured
Write-Step "Installing Windows Cursor hooks"
& (Join-Path $HarnessDir "install-hooks.ps1")

switch ($Action) {
    "hooks" {
        Write-Host "Cursor hooks configured for Windows."
        exit 0
    }
    "add-rule" {
        $addRule = Join-Path $HarnessDir "add-rule.ps1"
        $params = @{}
        if ($RuleName) { $params.Name = $RuleName }
        if ($RuleDescription) { $params.Description = $RuleDescription }
        if ($AlwaysApply) { $params.AlwaysApply = $true }
        if ($Globs) { $params.Globs = $Globs }
        if ($ContentFile) { $params.ContentFile = $ContentFile }
        & $addRule @params
        exit $LASTEXITCODE
    }
    "verify" {
        Write-Step "Running smoke verify"
        & $VerifyCmd
        exit $LASTEXITCODE
    }
    default {
        Write-Step "Running smoke verify"
        & $VerifyCmd
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }

        if ([string]::IsNullOrWhiteSpace($AssignmentFolder)) {
            Write-Host "Assignment folder required for action: $Action"
            exit 1
        }

        $assignPath = Resolve-AssignmentPath $AssignmentFolder
        Write-Step "Terraform $Action in $AssignmentFolder"

        if ($AssignmentFolder -match '(?i)day2[/\\]002' -and $Action -in @("plan", "apply", "destroy", "validate")) {
            . (Join-Path $BuildDir "cleanup-wsc2026-day2.ps1")
            Ensure-Day2002Tfvars -AssignPath $assignPath
        }

        switch ($Action) {
            "init" {
                & $TfCmd -chdir="$assignPath" init -input=false
            }
            "validate" {
                & $TfCmd -chdir="$assignPath" init -input=false
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                & $TfCmd -chdir="$assignPath" validate
            }
            "plan" {
                & $TfCmd -chdir="$assignPath" init -input=false
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                & $TfCmd -chdir="$assignPath" validate
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                & $TfCmd -chdir="$assignPath" plan -input=false
            }
            "apply" {
                & $TfCmd -chdir="$assignPath" init -input=false
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                & $TfCmd -chdir="$assignPath" validate
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                & $TfCmd -chdir="$assignPath" plan -input=false
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                & $TfCmd -chdir="$assignPath" apply -input=false -auto-approve
            }
            "destroy" {
                & $TfCmd -chdir="$assignPath" init -input=false
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                & $TfCmd -chdir="$assignPath" destroy -input=false -auto-approve
            }
        }
        exit $LASTEXITCODE
    }
}
