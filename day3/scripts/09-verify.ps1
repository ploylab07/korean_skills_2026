param(
    [string]$Endpoint = ""
)
. (Join-Path $PSScriptRoot "lib.ps1")
foreach ($cmd in @("curl.exe", "kubectl")) { Require-Command $cmd }
Ensure-CoreState
Ensure-Kubeconfig

if (-not $Endpoint) {
    $endpointFile = Join-Path $Script:Root '.public-endpoint'
    if (Test-Path $endpointFile) { $Endpoint = (Get-Content $endpointFile -Raw).Trim() }
}
if (-not $Endpoint -and (Test-Path (Join-Path $Script:EdgeDir 'terraform.tfstate'))) {
    $Endpoint = ((& terraform "-chdir=$Script:EdgeDir" output -raw public_endpoint) | Out-String).Trim()
}
if (-not $Endpoint) { Fail "Public endpoint not found. Run 07-create-single-endpoint.ps1 first." }
$Endpoint = $Endpoint.TrimEnd('/')

function Test-HttpCode {
    param([int]$Expected, [string]$Url)
    $actual = ((& curl.exe -ksS -o NUL -w '%{http_code}' $Url) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { Fail "curl failed for $Url" }
    Write-Host ("{0,-60} expected={1} actual={2}" -f $Url,$Expected,$actual)
    if ($actual -ne $Expected.ToString()) { Fail "Unexpected HTTP status for $Url" }
}

Write-Step "Kubernetes status"
Invoke-Kubectl -n app get 'pods,svc,hpa,ingress'

Write-Step "Endpoint behavior"
Test-HttpCode 200 "$Endpoint/healthcheck"
Test-HttpCode 403 "$Endpoint/v1/user"
Test-HttpCode 404 "$Endpoint/v1/none"

Write-Host "`nEndpoint to submit to the grading platform:" -ForegroundColor Cyan
Write-Host $Endpoint -ForegroundColor Green
Write-Host "Do not append /v1 or any other path."
