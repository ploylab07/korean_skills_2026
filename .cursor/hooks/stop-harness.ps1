# On agent stop: remind harness verification (Windows)
$ErrorActionPreference = "Stop"

$inputJson = [Console]::In.ReadToEnd()
$root = ""
try {
    $root = (git rev-parse --show-toplevel 2>$null)
}
catch {
    $root = (Get-Location).Path
}
if (-not $root) { $root = (Get-Location).Path }

$hasTf = $false
Get-ChildItem -Path $root -Filter "*.tf" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.terraform\\' -and $_.FullName -notmatch '\\build\\smoke\\' } |
    Select-Object -First 1 |
    ForEach-Object { $hasTf = $true }

if ($hasTf) {
    $msg = "Terraform 작업이 있었습니다. 완료 전: .\verify.cmd && .\run.cmd <과제폴더> plan (Windows) 또는 ./build/verify.sh (Linux). 채점 기준 대조도 잊지 마세요."
}
else {
    $msg = "작업 종료 전 .\verify.cmd (Windows) 또는 ./build/verify.sh (Linux)로 래퍼·환경을 확인하세요."
}

$output = @{
    followup_message = $msg
} | ConvertTo-Json -Compress

Write-Output $output
