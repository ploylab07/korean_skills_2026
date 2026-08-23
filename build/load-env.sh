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
}
