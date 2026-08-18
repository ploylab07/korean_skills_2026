# Wait for CodeBuild to finish (Windows contest apply).
# Encoding: UTF-8 with BOM
param()
$ErrorActionPreference = "Stop"
$Project = $env:TF_CB_PROJECT
$Region = if ($env:TF_CB_REGION) { $env:TF_CB_REGION } else { $env:AWS_DEFAULT_REGION }
if (-not $Project) { throw "TF_CB_PROJECT not set" }
if (-not $Region) { $Region = "ap-northeast-2" }

Write-Host "Starting CodeBuild: $Project (region=$Region)"
$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$buildId = & aws codebuild start-build --region $Region --project-name $Project --query "build.id" --output text 2>&1
$ErrorActionPreference = $prev
if ($LASTEXITCODE -ne 0) { throw "codebuild start-build failed: $buildId" }
Write-Host "Build id: $buildId"

for ($i = 1; $i -le 90; $i++) {
    $ErrorActionPreference = "Continue"
    $status = & aws codebuild batch-get-builds --region $Region --ids $buildId --query "builds[0].buildStatus" --output text 2>&1
    $phase = & aws codebuild batch-get-builds --region $Region --ids $buildId --query "builds[0].currentPhase" --output text 2>&1
    $ErrorActionPreference = $prev
    Write-Host "[$i] status=$status phase=$phase"
    switch ($status) {
        "SUCCEEDED" { Write-Host "CodeBuild SUCCEEDED"; exit 0 }
        { $_ -in @("FAILED", "FAULT", "STOPPED", "TIMED_OUT") } {
            Write-Host "CodeBuild failed: $status"
            & aws codebuild batch-get-builds --region $Region --ids $buildId --query "builds[0].phases" --output json 2>$null
            exit 1
        }
    }
    Start-Sleep -Seconds 10
}
Write-Host "Timed out waiting for CodeBuild"
exit 1
