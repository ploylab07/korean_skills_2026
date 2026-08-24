function Import-RepoEnv {
    param(
        [string]$BuildDir
    )

    $repoRoot = Split-Path -Parent $BuildDir
    $envFile = Join-Path $repoRoot ".env"

    if (-not (Test-Path $envFile)) {
        return
    }

    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { return }

        $name = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
        Set-Item -Path "env:$name" -Value $value
    }

    # day2/002 (and similar) — terraform.tfvars is gitignored; use .env instead.
    if ($env:PARTICIPANT_ID -and -not $env:TF_VAR_participant_id) {
        $env:TF_VAR_participant_id = $env:PARTICIPANT_ID
    }
    # day3 — portable across AWS accounts / contest PCs via .env
    if ($env:DB_PASSWORD -and -not $env:TF_VAR_db_password) {
        $env:TF_VAR_db_password = $env:DB_PASSWORD
    }
    if ($env:DAY3_PROJECT -and -not $env:TF_VAR_project) {
        $env:TF_VAR_project = $env:DAY3_PROJECT
    }
    if ($env:DAY3_ENVIRONMENT -and -not $env:TF_VAR_environment) {
        $env:TF_VAR_environment = $env:DAY3_ENVIRONMENT
    }
    if ($env:DB_IDENTIFIER -and -not $env:TF_VAR_db_identifier) {
        $env:TF_VAR_db_identifier = $env:DB_IDENTIFIER
    }
}
