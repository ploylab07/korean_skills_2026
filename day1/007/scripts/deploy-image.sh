#!/usr/bin/env bash
# Builds the Book App image and pushes v1.0.0 + latest to unicorn-concert-app.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/unicorn-concert-app"

aws ecr get-login-password --region "$AWS_DEFAULT_REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"

docker build -t "${REPO_URL}:v1.0.0" -t "${REPO_URL}:latest" "$ROOT"
docker push "${REPO_URL}:v1.0.0"
docker push "${REPO_URL}:latest"

echo "Pushed ${REPO_URL}:v1.0.0 and :latest"
