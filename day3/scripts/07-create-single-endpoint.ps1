param()
. (Join-Path $PSScriptRoot "lib.ps1")
foreach ($cmd in @("terraform", "kubectl", "aws")) { Require-Command $cmd }
Ensure-CoreState
Ensure-Kubeconfig

$albDns = ((& kubectl -n app get ingress application -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}' 2>$null) | Out-String).Trim()
if (-not $albDns) { Fail "ALB Ingress address is empty. Run 06-deploy-k8s.ps1 first." }

$region = Get-AwsRegion
$bucket = Get-TfOutputRaw "image_bucket_name"
$project = Get-ProjectName

Write-Step "Create CloudFront single HTTPS endpoint"
Invoke-EdgeTf init -upgrade
Invoke-EdgeTf fmt -recursive
Invoke-EdgeTf validate
Invoke-EdgeTf apply -auto-approve "-var=aws_region=$region" "-var=project_name=$project" "-var=alb_dns_name=$albDns" "-var=image_bucket_name=$bucket"

$endpoint = ((& terraform "-chdir=$Script:EdgeDir" output -raw public_endpoint) | Out-String).Trim()
Assert-NativeSuccess "terraform edge output"
[IO.File]::WriteAllText((Join-Path $Script:Root '.public-endpoint'), $endpoint, [Text.UTF8Encoding]::new($false))

Write-Host "`nPublic grading endpoint:"
Write-Host $endpoint -ForegroundColor Green
Write-Host "`nRouting:"
Write-Host "  /images/*  -> private S3 through CloudFront OAC"
Write-Host "  all others -> ALB -> EKS"
