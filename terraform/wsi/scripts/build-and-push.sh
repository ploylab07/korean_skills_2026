#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
ABOUT_REPO_URL="${ABOUT_REPO_URL:?ABOUT_REPO_URL is required}"
PROJECTS_REPO_URL="${PROJECTS_REPO_URL:?PROJECTS_REPO_URL is required}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> ECR 로그인 (${REGION})"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ABOUT_REPO_URL%/*}"

build_and_push() {
  local app_name="$1"
  local repo_url="$2"
  local context_dir="${ROOT_DIR}/apps/${app_name}"

  echo "==> Building ${app_name} image"
  docker build -t "${repo_url}:latest" "${context_dir}"

  echo "==> Pushing ${app_name} image"
  docker push "${repo_url}:latest"
}

build_and_push "about" "${ABOUT_REPO_URL}"
build_and_push "projects" "${PROJECTS_REPO_URL}"

echo "==> Done. ECR scan 결과는 AWS 콘솔에서 확인하세요."
