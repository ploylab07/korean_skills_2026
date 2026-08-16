# Add or update a Cursor rule (.cursor/rules/*.mdc)
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$Description,

    [switch]$AlwaysApply,
    [string]$Globs = "",
    [string]$ContentFile = "",
    [string]$Body = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$RulesDir = Join-Path $Root ".cursor\rules"
$Template = Join-Path $PSScriptRoot "templates\rule.mdc.template"

if (-not (Test-Path $RulesDir)) {
    New-Item -ItemType Directory -Force -Path $RulesDir | Out-Null
}

$slug = ($Name -replace '[^a-zA-Z0-9\-]+', '-').ToLower().Trim('-')
$ruleFile = Join-Path $RulesDir "$slug.mdc"

if ($ContentFile) {
    if (-not (Test-Path $ContentFile)) {
        throw "Content file not found: $ContentFile"
    }
    $Body = Get-Content $ContentFile -Raw
}

if ([string]::IsNullOrWhiteSpace($Body)) {
    $Body = @'
## 규칙

- (여기에 규칙 내용을 작성하세요)

## 예시

```
# good / bad 예시
```
'@
}

$globsLine = ""
if ($Globs -and -not $AlwaysApply) {
    $globsLine = "globs: $Globs`n"
}

$always = if ($AlwaysApply) { "true" } else { "false" }
$title = ($Name -replace '-', ' ')

$template = Get-Content $Template -Raw
$content = $template `
    -replace '\{\{DESCRIPTION\}\}', $Description `
    -replace '\{\{GLOBS_LINE\}\}', $globsLine `
    -replace '\{\{ALWAYS_APPLY\}\}', $always `
    -replace '\{\{TITLE\}\}', $title `
    -replace '\{\{BODY\}\}', $Body.Trim()

Set-Content -Path $ruleFile -Value $content -Encoding UTF8
Write-Host "Rule written: $ruleFile" -ForegroundColor Green
