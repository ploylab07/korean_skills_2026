# Windows (Docker Desktop): run the same win-test image as Linux
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ComposeFile = Join-Path $Root "build\docker\docker-compose.yml"
$Image = "korean-skills-2026-win-test"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker not found. Install Docker Desktop."
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "docker daemon is not running. Start Docker Desktop and retry."
}

$envFile = Join-Path $Root ".env"
if (Test-Path $envFile) {
    . (Join-Path $Root "build\load-env.ps1")
    Import-RepoEnv -BuildDir (Join-Path $Root "build")
}

Write-Host ">>> building $Image" -ForegroundColor Cyan
docker compose -f $ComposeFile build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> running win-test" -ForegroundColor Cyan
docker compose -f $ComposeFile run --rm `
    -e "AWS_ACCESS_KEY_ID=$($env:AWS_ACCESS_KEY_ID)" `
    -e "AWS_SECRET_ACCESS_KEY=$($env:AWS_SECRET_ACCESS_KEY)" `
    -e "AWS_DEFAULT_REGION=$($env:AWS_DEFAULT_REGION)" `
    win-test
exit $LASTEXITCODE
