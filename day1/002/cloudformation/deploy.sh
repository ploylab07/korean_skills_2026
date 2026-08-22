#!/usr/bin/env bash
# wskorea26 day1/002 CloudFormation package + deploy helper
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
BIBUN="${BIBUN:-${1:-001}}"
STACK_NAME="${STACK_NAME:-wskorea26-${BIBUN}}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-\$korea26!!}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PKG_BUCKET="${PKG_BUCKET:-wskorea26-cfn-packages-${ACCOUNT_ID}-${REGION}}"

if ! aws s3api head-bucket --bucket "$PKG_BUCKET" 2>/dev/null; then
  echo "Creating packaging bucket: $PKG_BUCKET"
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$PKG_BUCKET" --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$PKG_BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi

PACKAGED="${SCRIPT_DIR}/packaged.yaml"
aws cloudformation package \
  --template-file master.yaml \
  --s3-bucket "$PKG_BUCKET" \
  --s3-prefix "wskorea26/${BIBUN}" \
  --output-template-file "$PACKAGED" \
  --region "$REGION"

aws cloudformation deploy \
  --template-file "$PACKAGED" \
  --stack-name "$STACK_NAME" \
  --parameter-overrides \
    "Bibun=${BIBUN}" \
    "GrafanaAdminPassword=${GRAFANA_ADMIN_PASSWORD}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --no-fail-on-empty-changeset

echo ""
echo "=== Stack outputs ==="
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs' \
  --output table

S3_BUCKET="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" --output text)"
ECR_URI="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" --output text)"
CLUSTER="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text)"
CF_DOMAIN="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDomainName'].OutputValue" --output text)"
S3_KMS_ARN="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='S3KmsKeyArn'].OutputValue" --output text)"

PARENT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "=== Post-deploy steps ==="
echo "1. Upload S3 static assets (SSE-KMS):"
echo "   aws s3 cp ${PARENT_DIR}/index.html s3://${S3_BUCKET}/web/main/index.html \\"
echo "     --sse aws:kms --sse-kms-key-id ${S3_KMS_ARN} --content-type text/html"
echo "   aws s3 cp ${PARENT_DIR}/main.jpeg s3://${S3_BUCKET}/web/main/main.jpeg \\"
echo "     --sse aws:kms --sse-kms-key-id ${S3_KMS_ARN} --content-type image/jpeg"
echo ""
echo "2. Build and push book image to ECR (:stable):"
echo "   aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI%%/*}"
echo "   docker build -t ${ECR_URI}:stable ${PARENT_DIR}"
echo "   docker push ${ECR_URI}:stable"
echo ""
echo "3. Configure kubectl and apply Kubernetes manifests:"
echo "   aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER}"
echo "   kubectl apply -f ${PARENT_DIR}/k8s/namespace.yaml"
echo "   kubectl apply -f ${PARENT_DIR}/k8s/book-deploy.yaml"
echo "   kubectl apply -f ${PARENT_DIR}/k8s/monitoring/  # or helm install kube-prometheus-stack"
echo ""
echo "4. CloudFront URL: https://${CF_DOMAIN}/"
echo "   Grafana admin: skills-${BIBUN}-admin / (password from GrafanaAdminPassword parameter)"
