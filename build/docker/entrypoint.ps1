# Runs inside PowerShell Docker image on Linux — mirrors Windows harness checks
param()

$ErrorActionPreference = "Stop"
$Root = "/repo"

Set-Location $Root

Write-Host "=== Docker Windows-workflow test (PowerShell on Linux) ===" -ForegroundColor Cyan
Write-Host "repo: $Root"
Write-Host "pwsh: $($PSVersionTable.PSVersion)"

$fail = 0
$hooksBackup = $null
$hooksFile = Join-Path $Root ".cursor/hooks.json"

function Assert-File([string]$Path) {
    if (-not (Test-Path $Path)) {
        Write-Host "[FAIL] missing: $Path" -ForegroundColor Red
        $script:fail++
        return
    }
    Write-Host "[OK] $Path" -ForegroundColor Green
}

# Preserve host hooks.json (Linux may use .sh paths)
if (Test-Path $hooksFile) {
    $hooksBackup = Get-Content -Raw -Path $hooksFile
}

Assert-File "$Root/run.cmd"
Assert-File "$Root/verify.cmd"
Assert-File "$Root/build/verify.ps1"
Assert-File "$Root/build/run.ps1"
Assert-File "$Root/build/harness/add-rule.ps1"
Assert-File "$Root/build/harness/install-hooks.ps1"
Assert-File "$Root/.cursor/hooks/after-tf-edit.ps1"
Assert-File "$Root/.cursor/hooks/stop-harness.ps1"
Assert-File "$Root/build/smoke/main.tf"

Write-Host ""
Write-Host ">>> install-hooks.ps1" -ForegroundColor Cyan
& "$Root/build/harness/install-hooks.ps1"
if (-not $?) { $fail++ }

Write-Host ""
Write-Host ">>> verify.ps1 (smoke)" -ForegroundColor Cyan
& "$Root/build/verify.ps1"
if (-not $?) { $fail++ }

Write-Host ""
Write-Host ">>> add-rule.ps1 (dry run)" -ForegroundColor Cyan
& "$Root/build/harness/add-rule.ps1" `
    -Name "docker-test-rule" `
    -Description "Auto-generated test rule — safe to delete" `
    -Body "## Test`n`nDocker harness smoke test."
if (-not $?) {
    $fail++
}
else {
    $testRule = "$Root/.cursor/rules/docker-test-rule.mdc"
    if (Test-Path $testRule) {
        Remove-Item $testRule -Force
        Write-Host "[OK] test rule cleaned up" -ForegroundColor Green
    }
}

# Restore host hooks.json so Linux/.sh config is not overwritten permanently
if ($null -ne $hooksBackup) {
    Set-Content -Path $hooksFile -Value $hooksBackup -Encoding UTF8 -NoNewline
    Write-Host "[OK] restored host hooks.json" -ForegroundColor Green
}

Write-Host ""
if ($fail -gt 0) {
    Write-Host "=== FAILED ($fail checks) ===" -ForegroundColor Red
    exit 1
}

Write-Host "=== ALL PASSED ===" -ForegroundColor Green
exit 0
