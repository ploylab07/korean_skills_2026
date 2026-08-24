param()
. (Join-Path $PSScriptRoot "lib.ps1")

foreach ($cmd in @("aws", "git", "kubectl")) { Require-Command $cmd }
Ensure-Day3Tfvars

Write-Step "Initialize and validate core Terraform"
Invoke-Tf init -upgrade
Invoke-Tf fmt -recursive
Invoke-Tf validate

Write-Step "Bootstrap VPC and EKS"
Invoke-Tf plan '-target=module.vpc' '-target=module.eks' '-out=bootstrap.tfplan'
Invoke-Tf apply 'bootstrap.tfplan'
Remove-Item (Join-Path $Script:TfDir 'bootstrap.tfplan') -Force -ErrorAction SilentlyContinue

Write-Step "Configure kubectl"
Ensure-Kubeconfig
Invoke-Kubectl get nodes

Write-Step "Apply complete core infrastructure"
Invoke-Tf plan '-out=tfplan'
Invoke-Tf apply 'tfplan'
Remove-Item (Join-Path $Script:TfDir 'tfplan') -Force -ErrorAction SilentlyContinue

Write-Step "Core infrastructure completed"
Invoke-Tf output
Write-Host "`nNext: .\scripts\10-complete-after-apply.ps1  (or step through 02..09)"
Write-Host "Place contest binaries in apps\ and dump\load_user.dump first."
