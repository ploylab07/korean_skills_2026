#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1. verify ==="
"$ROOT/build/verify.sh"

echo "=== 2. terraform apply ==="
"$ROOT/terraform" -chdir="$DIR" init -input=false
"$ROOT/terraform" -chdir="$DIR" apply -auto-approve "$@"

echo "=== 3. docker build & push (local) ==="
ECR_URL=$("$ROOT/terraform" -chdir="$DIR" output -raw ecr_repository_url)
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
docker build -t "$ECR_URL:v1.0.0" "$DIR"
docker push "$ECR_URL:v1.0.0"

echo "=== 4. post-deploy k8s ==="
export AWS_DEFAULT_REGION="$REGION"
bash "$DIR/scripts/post-deploy-k8s.sh"

echo "=== 완료 ==="
"$ROOT/terraform" -chdir="$DIR" output
