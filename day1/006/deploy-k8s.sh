#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export AWS_DEFAULT_REGION=ap-northeast-2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER=gj2026-eks-cluster
IMAGE="${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/book:latest"

aws eks update-kubeconfig --name "$CLUSTER" --region ap-northeast-2

# Rename Bottlerocket nodes to gj2026.<iid>.{addon|app}.node via SSM/API if needed
echo "== Node hostname fix =="
for ng in addon app; do
  label="gj2026=${ng}"
  # Prefer role label
  :
done

# Apply manifests
sed "s|IMAGE_PLACEHOLDER|${IMAGE}|g" k8s/book.yaml | kubectl apply -f -
kubectl apply -f k8s/fluentbit.yaml

# Wait for book
kubectl -n skills rollout status deploy/book --timeout=300s || true
kubectl -n skills get pods -o wide

# Register book pods to ALB target group (IP mode) if not using controller
TG_ARN=$(aws elbv2 describe-target-groups --names gj2026-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
for ip in $(kubectl -n skills get pods -l app=book -o jsonpath='{.items[*].status.podIP}'); do
  aws elbv2 register-targets --target-group-arn "$TG_ARN" --targets Id="$ip",Port=8080 || true
done

echo "Book targets:"
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --output table || true

# Fluent-bit needs CW logs permissions on node role — ensure attached
echo "Done k8s deploy"
