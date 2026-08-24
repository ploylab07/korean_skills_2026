param(
    [switch]$Force
)
. (Join-Path $PSScriptRoot "lib.ps1")

if (-not $Force) {
    $confirm = Read-Host "Type DESTROY to delete CloudFront, Kubernetes resources and AWS infrastructure"
    if ($confirm -ne 'DESTROY') { exit 0 }
}

if (Test-Path (Join-Path $Script:EdgeDir 'terraform.tfstate')) {
    Write-Step "Destroy CloudFront edge stack"
    Invoke-EdgeTf destroy -auto-approve
}
if ((Get-Command kubectl -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $Script:TfDir 'terraform.tfstate'))) {
    try {
        Ensure-Kubeconfig
        & kubectl delete namespace app --ignore-not-found --wait=true | Out-Host
    }
    catch {}
}
if (Test-Path (Join-Path $Script:TfDir 'terraform.tfstate')) {
    Write-Step "Destroy core infrastructure"
    Ensure-Day3Tfvars
    Invoke-Tf destroy -auto-approve
}

# Always wipe SameName leftovers (state may be empty after zip re-download).
$cleanup = Join-Path $Script:RepoRoot "build\cleanup-apdev-day3.ps1"
if (Test-Path -LiteralPath $cleanup) {
    Write-Step "Wipe leftover apdev-dev-* resources by name"
    . $cleanup
    $region = if ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { "ap-northeast-2" }
    Clear-ApdevDay3Leftovers -Region $region
}
Write-Host "Destroy finished."
