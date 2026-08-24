param(
    [string]$DbPassword = $(if ($env:DB_PASSWORD) { $env:DB_PASSWORD } elseif ($env:TF_VAR_db_password) { $env:TF_VAR_db_password } else { "" })
)
. (Join-Path $PSScriptRoot "lib.ps1")
foreach ($cmd in @("terraform", "aws", "kubectl")) { Require-Command $cmd }
Ensure-CoreState
Ensure-Kubeconfig

$region = Get-AwsRegion
$dbHost = Get-TfOutputRaw "rds_endpoint"
$dbPort = Get-TfOutputRaw "rds_port"
$dbName = Get-TfOutputRaw "db_name"
$dbUser = Get-TfOutputRaw "db_username"
$s3Bucket = Get-TfOutputRaw "image_bucket_name"

if ([string]::IsNullOrWhiteSpace($DbPassword)) {
    $secure = Read-Host "RDS password" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $DbPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
if ($DbPassword.Length -lt 8) { Fail "DB password must contain at least 8 characters." }

Write-Step "Create namespace and service accounts"
Invoke-Kubectl apply -f (Join-Path $Script:K8sDir "namespace-and-serviceaccounts.yaml")

$tempSecret = Join-Path ([IO.Path]::GetTempPath()) ("app-db-{0}.yaml" -f [guid]::NewGuid())
$tempConfig = Join-Path ([IO.Path]::GetTempPath()) ("app-config-{0}.yaml" -f [guid]::NewGuid())
try {
    Write-Step "Create/update application DB Secret"
    $secretYaml = & kubectl -n app create secret generic app-db `
        "--from-literal=MYSQL_HOST=$dbHost" `
        "--from-literal=MYSQL_PORT=$dbPort" `
        "--from-literal=MYSQL_DBNAME=$dbName" `
        "--from-literal=MYSQL_USER=$dbUser" `
        "--from-literal=MYSQL_PASSWORD=$DbPassword" `
        --dry-run=client -o yaml
    Assert-NativeSuccess "kubectl create secret"
    [IO.File]::WriteAllText($tempSecret, ($secretYaml -join "`n"), [Text.UTF8Encoding]::new($false))
    Invoke-Kubectl apply -f $tempSecret

    Write-Step "Create/update application ConfigMap"
    $configYaml = & kubectl -n app create configmap app-config `
        "--from-literal=AWS_REGION=$region" `
        "--from-literal=S3_BUCKET=$s3Bucket" `
        "--from-literal=AWS_S3_BUCKET=$s3Bucket" `
        "--from-literal=S3_REGION=$region" `
        '--from-literal=TZ=Asia/Seoul' `
        --dry-run=client -o yaml
    Assert-NativeSuccess "kubectl create configmap"
    [IO.File]::WriteAllText($tempConfig, ($configYaml -join "`n"), [Text.UTF8Encoding]::new($false))
    Invoke-Kubectl apply -f $tempConfig
}
finally {
    Remove-Item $tempSecret,$tempConfig -Force -ErrorAction SilentlyContinue
}

Invoke-Kubectl -n app get secret app-db
Invoke-Kubectl -n app get configmap app-config
