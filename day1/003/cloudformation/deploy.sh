#!/usr/bin/env bash
# wsc2026 day1/003 CloudFormation package + deploy helper
# Regional stack (ap-northeast-2) + CDN/WAF stack (us-east-1)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
BIBUN="${BIBUN:-${1:-003}}"
BUCKET_SUFFIX="${BUCKET_SUFFIX:-skil}"
STACK_NAME="${STACK_NAME:-wsc2026-${BIBUN}}"
CDN_STACK_NAME="${CDN_STACK_NAME:-${STACK_NAME}-cdn}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-Skills\$#\$@!}"
CF_PREFIX_LIST="${CF_PREFIX_LIST:-pl-58a04531}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PKG_BUCKET="${PKG_BUCKET:-wsc2026-cfn-packages-${ACCOUNT_ID}-${REGION}}"

stack_out() {
  local stack="$1" key="$2" region="$3"
  aws cloudformation describe-stacks \
    --stack-name "$stack" \
    --region "$region" \
    --query "Stacks[0].Outputs[?OutputKey=='${key}'].OutputValue" \
    --output text
}

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

PACKAGED="${SCRIPT_DIR}/packaged-master.yaml"
aws cloudformation package \
  --template-file master.yaml \
  --s3-bucket "$PKG_BUCKET" \
  --s3-prefix "wsc2026/${BIBUN}/master" \
  --output-template-file "$PACKAGED" \
  --region "$REGION"

aws cloudformation deploy \
  --template-file "$PACKAGED" \
  --stack-name "$STACK_NAME" \
  --parameter-overrides \
    "Bibun=${BIBUN}" \
    "BucketSuffix=${BUCKET_SUFFIX}" \
    "CloudFrontPrefixListId=${CF_PREFIX_LIST}" \
    "GrafanaAdminPassword=${GRAFANA_ADMIN_PASSWORD}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --no-fail-on-empty-changeset

echo ""
echo "=== Regional stack outputs ==="
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs' \
  --output table

S3_BUCKET="$(stack_out "$STACK_NAME" S3BucketName "$REGION")"
S3_ARN="$(stack_out "$STACK_NAME" S3BucketArn "$REGION")"
S3_REGIONAL_DNS="$(stack_out "$STACK_NAME" S3BucketRegionalDomainName "$REGION")"
ECR_URI="$(stack_out "$STACK_NAME" EcrRepositoryUri "$REGION")"
CLUSTER="$(stack_out "$STACK_NAME" ClusterName "$REGION")"
ALB_DNS="$(stack_out "$STACK_NAME" AlbDnsName "$REGION")"
LAMBDA_URL="$(stack_out "$STACK_NAME" LambdaFunctionUrl "$REGION")"
BUCKET_KMS_ARN="$(stack_out "$STACK_NAME" BucketKmsKeyArn "$REGION")"

LAMBDA_HOST="${LAMBDA_URL#https://}"
LAMBDA_HOST="${LAMBDA_HOST%/}"

echo ""
echo "=== Deploying CDN/WAF stack in us-east-1 ==="
CDN_PACKAGED="${SCRIPT_DIR}/packaged-cdn.yaml"
cp cdn.yaml "$CDN_PACKAGED"

aws cloudformation deploy \
  --template-file "$CDN_PACKAGED" \
  --stack-name "$CDN_STACK_NAME" \
  --parameter-overrides \
    "S3BucketName=${S3_BUCKET}" \
    "S3BucketArn=${S3_ARN}" \
    "S3BucketRegionalDomainName=${S3_REGIONAL_DNS}" \
    "AlbDnsName=${ALB_DNS}" \
    "LambdaFunctionUrlHost=${LAMBDA_HOST}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --no-fail-on-empty-changeset

CF_DOMAIN="$(stack_out "$CDN_STACK_NAME" CloudFrontDomainName us-east-1)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "=== CDN outputs ==="
aws cloudformation describe-stacks \
  --stack-name "$CDN_STACK_NAME" \
  --region us-east-1 \
  --query 'Stacks[0].Outputs' \
  --output table

echo ""
echo "=== Post-deploy steps ==="
echo "1. Upload S3 static assets (SSE-KMS):"
echo "   aws s3 cp ${PARENT_DIR}/index.html s3://${S3_BUCKET}/static/index.html \\"
echo "     --sse aws:kms --sse-kms-key-id ${BUCKET_KMS_ARN} --content-type text/html"
echo "   aws s3 cp ${PARENT_DIR}/main.jpeg s3://${S3_BUCKET}/static/main.jpeg \\"
echo "     --sse aws:kms --sse-kms-key-id ${BUCKET_KMS_ARN} --content-type image/jpeg"
echo "   aws s3 cp ${PARENT_DIR}/main.jpeg s3://${S3_BUCKET}/main.jpeg \\"
echo "     --sse aws:kms --sse-kms-key-id ${BUCKET_KMS_ARN} --content-type image/jpeg"
echo ""
echo "2. Build and push book image to ECR (:v1.0.0 only):"
echo "   aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI%%/*}"
echo "   docker build -t ${ECR_URI}:v1.0.0 ${PARENT_DIR}"
echo "   docker push ${ECR_URI}:v1.0.0"
echo ""
echo "3. Configure kubectl (via bastion/SSM) and apply Kubernetes manifests:"
echo "   aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER}"
echo "   kubectl apply -f ${PARENT_DIR}/k8s/"
echo ""
echo "4. CloudFront URL: https://${CF_DOMAIN}/"
echo "   Grafana password: Skills\$#\$@! (or GrafanaAdminPassword)"
