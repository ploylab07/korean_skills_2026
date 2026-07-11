# After .tf edit: suggest terraform validate in the edited file's directory (Windows)
$ErrorActionPreference = "Stop"

$inputJson = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputJson)) { exit 0 }

try {
    $data = $inputJson | ConvertFrom-Json
}
catch {
    exit 0
}

$filePath = $data.file_path
if (-not $filePath) { $filePath = $data.path }
if ([string]::IsNullOrWhiteSpace($filePath) -or $filePath -notmatch '\.tf$') {
    exit 0
}

$dir = Split-Path -Parent $filePath
$root = ""
try {
    $root = (git rev-parse --show-toplevel 2>$null)
}
catch {
    $root = (Get-Location).Path
}
if (-not $root) { $root = (Get-Location).Path }

$msg = "Terraform 파일이 수정됨: $filePath. 검증: .\run.cmd `"$dir`" plan (Windows) 또는 ./terraform -chdir=$dir validate (Linux). 완료 전 verify도 실행."

$output = @{
    additional_context = $msg
} | ConvertTo-Json -Compress

Write-Output $output
