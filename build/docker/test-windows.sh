#!/usr/bin/env bash
# Linux dev: run Windows harness workflow inside Docker (PowerShell Core)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="korean-skills-2026-win-test"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. Install Docker to test Windows workflow on Linux." >&2
  exit 1
fi

# Load .env for plan test inside container (optional)
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck source=build/load-env.sh
  source "$ROOT/build/load-env.sh"
  load_repo_env "$ROOT/build"
  set +a
fi

docker build -t "$IMAGE" -f "$ROOT/build/docker/Dockerfile" "$ROOT"

docker run --rm \
  -v "$ROOT:/repo" \
  -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-}" \
  -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-}" \
  -e "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-2}" \
  "$IMAGE"
