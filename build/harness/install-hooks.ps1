# Configure Cursor hooks for Windows (PowerShell hooks)
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$HooksFile = Join-Path $Root ".cursor\hooks.json"
$HooksDir = Join-Path $Root ".cursor\hooks"

$hooks = @{
    version = 1
    hooks   = @{
        afterFileEdit = @(
            @{
                command = ".cursor/hooks/after-tf-edit.ps1"
                matcher = "\.tf$"
            }
        )
        stop          = @(
            @{
                command = ".cursor/hooks/stop-harness.ps1"
            }
        )
    }
}

if (-not (Test-Path $HooksDir)) {
    New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null
}

$json = $hooks | ConvertTo-Json -Depth 6
Set-Content -Path $HooksFile -Value $json -Encoding UTF8
Write-Host "Windows hooks installed: $HooksFile"
