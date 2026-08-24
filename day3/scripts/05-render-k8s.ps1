param(
    [string]$ImageTag = $env:IMAGE_TAG
)
. (Join-Path $PSScriptRoot "lib.ps1")
Require-Command "terraform"
Ensure-CoreState

$outDir = Join-Path $Script:K8sDir "rendered"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
if (-not $ImageTag) {
    $tagFile = Join-Path $Script:Root '.image-tag'
    if (Test-Path $tagFile) { $ImageTag = (Get-Content $tagFile -Raw).Trim() }
}
if (-not $ImageTag) { $ImageTag = "latest" }

$repos = (Get-TfOutputJson "ecr_repository_urls") | ConvertFrom-Json
$wafArn = Get-TfOutputRaw "waf_acl_arn"
$logBucket = Get-TfOutputRaw "alb_log_bucket_name"
$albSgId = Get-TfOutputRaw "alb_security_group_id"
$albName = "$(Get-ProjectName)-alb"
if ($albName.Length -gt 32) { $albName = $albName.Substring(0,32) }

$appText = Get-Content (Join-Path $Script:K8sDir 'app-template.yaml') -Raw
$appText = $appText.Replace('IMAGE_URI_USER', "$($repos.user):$ImageTag")
$appText = $appText.Replace('IMAGE_URI_PRODUCT', "$($repos.product):$ImageTag")
$appText = $appText.Replace('IMAGE_URI_STRESS', "$($repos.stress):$ImageTag")
[IO.File]::WriteAllText((Join-Path $outDir 'apps.yaml'), $appText, [Text.UTF8Encoding]::new($false))

$ingressText = Get-Content (Join-Path $Script:K8sDir 'ingress-template.yaml') -Raw
$ingressText = $ingressText.Replace('WAF_ACL_ARN', $wafArn)
$ingressText = $ingressText.Replace('ALB_LOG_BUCKET', $logBucket)
$ingressText = $ingressText.Replace('ALB_SECURITY_GROUP_ID', $albSgId)
$ingressText = $ingressText.Replace('ALB_NAME', $albName)
[IO.File]::WriteAllText((Join-Path $outDir 'ingress.yaml'), $ingressText, [Text.UTF8Encoding]::new($false))

$combined = (Get-Content (Join-Path $outDir 'apps.yaml') -Raw) + (Get-Content (Join-Path $outDir 'ingress.yaml') -Raw)
if ($combined -match 'IMAGE_URI_|WAF_ACL_ARN|ALB_LOG_BUCKET|ALB_SECURITY_GROUP_ID|ALB_NAME') {
    Fail "Unrendered placeholders remain in $outDir"
}
Write-Step "Rendered Kubernetes manifests"
Write-Host (Join-Path $outDir 'apps.yaml')
Write-Host (Join-Path $outDir 'ingress.yaml')
