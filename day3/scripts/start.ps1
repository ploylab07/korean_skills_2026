# day3 Windows entry (also called from repo start.cmd after selecting day3).
# Encoding: UTF-8 with BOM
param(
    [ValidateSet("", "apply", "destroy", "post", "check")]
    [string]$Mode = "",
    [string]$Email = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib.ps1")

function Show-Menu {
    Write-Host ""
    Write-Host "=== day3 deploy ===" -ForegroundColor Cyan
    Write-Host "  [1] Apply infra + post-deploy (apps + dump required)"
    Write-Host "  [2] Apply infra only"
    Write-Host "  [3] Post-deploy only (after infra)"
    Write-Host "  [4] Destroy all"
    Write-Host "  [0] Exit"
    while ($true) {
        $c = Read-Host "Select"
        switch ($c) {
            "1" { return "full" }
            "2" { return "infra" }
            "3" { return "post" }
            "4" { return "destroy" }
            "0" { exit 0 }
            default { Write-Host "Invalid." -ForegroundColor Yellow }
        }
    }
}

if (-not $Mode) {
    $Mode = Show-Menu
}
elseif ($Mode -eq "apply") { $Mode = "full" }
elseif ($Mode -eq "check") {
    & (Join-Path $PSScriptRoot "00-check-tools.ps1")
    exit 0
}

switch ($Mode) {
    "destroy" {
        & (Join-Path $PSScriptRoot "99-destroy-all.ps1") -Force
    }
    "infra" {
        & (Join-Path $PSScriptRoot "00-check-tools.ps1")
        & (Join-Path $PSScriptRoot "01-apply-infra.ps1")
    }
    "post" {
        & (Join-Path $PSScriptRoot "10-complete-after-apply.ps1") -Email $Email
    }
    "full" {
        & (Join-Path $PSScriptRoot "00-check-tools.ps1")
        & (Join-Path $PSScriptRoot "01-apply-infra.ps1")
        & (Join-Path $PSScriptRoot "10-complete-after-apply.ps1") -Email $Email
    }
    default { throw "Unknown mode: $Mode" }
}

Write-Host ""
Write-Host "=== day3 finished ===" -ForegroundColor Green
