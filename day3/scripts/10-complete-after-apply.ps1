param(
    [string]$AppDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "apps"),
    [string]$DumpPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "dump\load_user.dump"),
    [string]$Email = ""
)
. (Join-Path $PSScriptRoot "lib.ps1")

if (-not (Test-Path $DumpPath -PathType Leaf)) { Fail "Place load_user.dump at $DumpPath or pass -DumpPath." }
foreach ($app in @('user','product','stress')) {
    if (-not (Test-Path (Join-Path $AppDir $app) -PathType Leaf)) { Fail "Place Linux binary '$app' in $AppDir or pass -AppDir." }
}

& (Join-Path $PSScriptRoot '02-create-runtime-config.ps1')
& (Join-Path $PSScriptRoot '03-init-rds.ps1') -DumpPath $DumpPath
& (Join-Path $PSScriptRoot '04-build-push-images.ps1') -AppDir $AppDir
& (Join-Path $PSScriptRoot '05-render-k8s.ps1')
& (Join-Path $PSScriptRoot '06-deploy-k8s.ps1')
& (Join-Path $PSScriptRoot '07-create-single-endpoint.ps1')
& (Join-Path $PSScriptRoot '08-configure-monitoring.ps1') -Email $Email
& (Join-Path $PSScriptRoot '09-verify.ps1')
