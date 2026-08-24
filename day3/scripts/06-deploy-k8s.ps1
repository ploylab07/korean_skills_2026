param()
. (Join-Path $PSScriptRoot "lib.ps1")
Require-Command "kubectl"
Ensure-CoreState
Ensure-Kubeconfig

$apps = Join-Path $Script:K8sDir 'rendered\apps.yaml'
$ingress = Join-Path $Script:K8sDir 'rendered\ingress.yaml'
if (-not (Test-Path $apps)) { Fail "Run 05-render-k8s.ps1 first." }
if (-not (Test-Path $ingress)) { Fail "Run 05-render-k8s.ps1 first." }

Write-Step "Deploy applications and ALB Ingress"
Invoke-Kubectl apply -f (Join-Path $Script:K8sDir 'namespace-and-serviceaccounts.yaml')
Invoke-Kubectl apply -f $apps
Invoke-Kubectl apply -f $ingress

foreach ($app in @('user','product','stress')) {
    Invoke-Kubectl -n app rollout status "deployment/$app" --timeout=10m
}

Write-Step "Wait for ALB address"
for ($i = 0; $i -lt 60; $i++) {
    $address = ((& kubectl -n app get ingress application -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}' 2>$null) | Out-String).Trim()
    if ($address) {
        Write-Host "ALB DNS: $address"
        exit 0
    }
    Start-Sleep -Seconds 10
}
Fail "ALB address was not assigned within 10 minutes."
