$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$EnvFile = Join-Path $RepoRoot ".env"

Write-Host "AWS 자격 증명 설정"
Write-Host "입력값은 $EnvFile 에 저장됩니다. (.gitignore 대상, Git에 올라가지 않음)"
Write-Host ""

$accessKey = Read-Host "AWS_ACCESS_KEY_ID"
$secretKey = Read-Host "AWS_SECRET_ACCESS_KEY" -AsSecureString
$region = Read-Host "AWS_DEFAULT_REGION [ap-northeast-2]"
if ([string]::IsNullOrWhiteSpace($region)) { $region = "ap-northeast-2" }

if ([string]::IsNullOrWhiteSpace($accessKey)) {
    throw "AWS_ACCESS_KEY_ID는 필수입니다."
}

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secretKey)
try {
    $plainSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

if ([string]::IsNullOrWhiteSpace($plainSecret)) {
    throw "AWS_SECRET_ACCESS_KEY는 필수입니다."
}

@"
# AWS credentials - do not commit
AWS_ACCESS_KEY_ID=$accessKey
AWS_SECRET_ACCESS_KEY=$plainSecret
AWS_DEFAULT_REGION=$region
"@ | Set-Content -Path $EnvFile -Encoding UTF8

Write-Host ""
Write-Host "저장 완료: $EnvFile"
Write-Host "이제 .\terraform.cmd 실행 시 자동으로 적용됩니다."
