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
    # day3 RDS password
    if ($env:DB_PASSWORD -and -not $env:TF_VAR_db_password) {
        $env:TF_VAR_db_password = $env:DB_PASSWORD
    }
}
