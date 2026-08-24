#!/usr/bin/env bash
# Load .env from repository root into the current shell environment.
load_repo_env() {
  local build_dir repo_root env_file
  build_dir="${1:?build directory required}"
  repo_root="$(cd "$build_dir/.." && pwd)"
  env_file="$repo_root/.env"

  if [[ ! -f "$env_file" ]]; then
    return 0
  fi

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  # day2/002 (and similar) — terraform.tfvars is gitignored; use .env instead.
  if [[ -n "${PARTICIPANT_ID:-}" && -z "${TF_VAR_participant_id:-}" ]]; then
    export TF_VAR_participant_id="$PARTICIPANT_ID"
  fi
  # day3 — portable across AWS accounts / contest PCs via .env
  if [[ -n "${DB_PASSWORD:-}" && -z "${TF_VAR_db_password:-}" ]]; then
    export TF_VAR_db_password="$DB_PASSWORD"
  fi
  if [[ -n "${DAY3_PROJECT:-}" && -z "${TF_VAR_project:-}" ]]; then
    export TF_VAR_project="$DAY3_PROJECT"
  fi
  if [[ -n "${DAY3_ENVIRONMENT:-}" && -z "${TF_VAR_environment:-}" ]]; then
    export TF_VAR_environment="$DAY3_ENVIRONMENT"
  fi
  if [[ -n "${DB_IDENTIFIER:-}" && -z "${TF_VAR_db_identifier:-}" ]]; then
    export TF_VAR_db_identifier="$DB_IDENTIFIER"
  fi
}
