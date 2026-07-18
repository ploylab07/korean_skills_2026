#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/book"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

chmod +x book-linux-amd64_v1.0.1
docker build -t book:latest -t book:v1.0.0 .
docker tag book:latest "${REPO}:latest"
docker tag book:v1.0.0 "${REPO}:v1.0.0"
docker push "${REPO}:latest"
docker push "${REPO}:v1.0.0"

echo "Pushed ${REPO}:latest"
aws ecr describe-images --repository-name book --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text
