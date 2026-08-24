param()
. (Join-Path $PSScriptRoot "lib.ps1")

$required = @("aws", "git", "kubectl")
foreach ($cmd in $required) { Require-Command $cmd }
# terraform via repo wrapper (terraform.cmd)
$null = Resolve-RepoTerraform

Write-Step "Tool versions"
& $Script:TfBin version
& aws --version
& git --version
& kubectl version --client

Write-Step "AWS identity"
& aws sts get-caller-identity
Assert-NativeSuccess "aws sts get-caller-identity"

Write-Host "Prerequisites OK (Docker Desktop not required; images build via CodeBuild)."
