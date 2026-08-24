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
Write-Host "Destroy finished."
