#!/usr/bin/env bash
# unicorn day1/007 CloudFormation package + deploy helper
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
BIBUN="${BIBUN:-${1:-007}}"
STACK_NAME="${STACK_NAME:-unicorn-${BIBUN}}"
USE1_STACK_NAME="${USE1_STACK_NAME:-unicorn-${BIBUN}-use1}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PKG_BUCKET="${PKG_BUCKET:-unicorn-cfn-packages-${ACCOUNT_ID}-${REGION}}"

echo "=== Resolve CloudFront origin-facing prefix list ==="
CF_PREFIX_LIST_ID="$(aws ec2 describe-managed-prefix-lists \
  --region "$REGION" \
  --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing \
  --query 'PrefixLists[0].PrefixListId' --output text)"
if [[ -z "$CF_PREFIX_LIST_ID" || "$CF_PREFIX_LIST_ID" == "None" ]]; then
  echo "ERROR: cloudfront.origin-facing managed prefix list not found in ${REGION}" >&2
  exit 1
fi
echo "PrefixListId=${CF_PREFIX_LIST_ID}"

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

echo ""
echo "=== Deploy us-east-1 (platform KMS primary + WAF) ==="
aws cloudformation deploy \
  --template-file us-east-1.yaml \
  --stack-name "$USE1_STACK_NAME" \
  --parameter-overrides "Bibun=${BIBUN}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --no-fail-on-empty-changeset

PLATFORM_KMS_PRIMARY_ARN="$(aws cloudformation describe-stacks \
  --stack-name "$USE1_STACK_NAME" --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='PlatformKmsPrimaryArn'].OutputValue" --output text)"
WEB_ACL_ARN="$(aws cloudformation describe-stacks \
  --stack-name "$USE1_STACK_NAME" --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='WebAclArn'].OutputValue" --output text)"

echo "PlatformKmsPrimaryArn=${PLATFORM_KMS_PRIMARY_ARN}"
echo "WebAclArn=${WEB_ACL_ARN}"

echo ""
echo "=== Package nested templates (${REGION}) ==="
PACKAGED="${SCRIPT_DIR}/packaged.yaml"
aws cloudformation package \
  --template-file master.yaml \
  --s3-bucket "$PKG_BUCKET" \
  --s3-prefix "unicorn/${BIBUN}" \
  --output-template-file "$PACKAGED" \
  --region "$REGION"

echo ""
echo "=== Deploy master stack ${STACK_NAME} ==="
aws cloudformation deploy \
  --template-file "$PACKAGED" \
  --stack-name "$STACK_NAME" \
  --parameter-overrides \
    "Bibun=${BIBUN}" \
    "PlatformKmsPrimaryArn=${PLATFORM_KMS_PRIMARY_ARN}" \
    "WebAclArn=${WEB_ACL_ARN}" \
    "CloudFrontOriginFacingPrefixListId=${CF_PREFIX_LIST_ID}" \
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
DATA_KMS_ARN="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='DataKmsKeyArn'].OutputValue" --output text)"
BOOK_APP_ROLE="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BookAppRoleArn'].OutputValue" --output text)"

PARENT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "=== Post-deploy steps ==="
echo "1. Upload S3 static assets (SSE-KMS):"
echo "   aws s3 cp ${PARENT_DIR}/index.html s3://${S3_BUCKET}/index.html \\"
echo "     --sse aws:kms --sse-kms-key-id ${DATA_KMS_ARN} --content-type text/html"
echo "   aws s3 cp ${PARENT_DIR}/main.jpeg s3://${S3_BUCKET}/main.jpeg \\"
echo "     --sse aws:kms --sse-kms-key-id ${DATA_KMS_ARN} --content-type image/jpeg"
echo ""
echo "2. Build and push book image to ECR (:v1.0.0 and :latest):"
echo "   aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI%%/*}"
echo "   docker build -t ${ECR_URI}:v1.0.0 ${PARENT_DIR}"
echo "   docker tag ${ECR_URI}:v1.0.0 ${ECR_URI}:latest"
echo "   docker push ${ECR_URI}:v1.0.0 && docker push ${ECR_URI}:latest"
echo ""
echo "3. Configure kubectl, apply k8s (book/monitoring), Pod Identity:"
echo "   aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER}"
echo "   # apply namespace unicorn/monitoring, SA unicorn-book-app-sa, deploy/svc, fluent-bit, kube-prometheus-stack"
echo "   aws eks create-pod-identity-association --cluster-name ${CLUSTER} \\"
echo "     --namespace unicorn --service-account unicorn-book-app-sa --role-arn ${BOOK_APP_ROLE}"
echo ""
echo "4. Register ALB IP targets for book/grafana pods (see scripts/register-alb-targets.sh)"
echo ""
echo "5. After k8s apply, lock EKS public endpoint:"
echo "   aws eks update-cluster-config --name ${CLUSTER} --region ${REGION} \\"
echo "     --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true"
echo ""
echo "6. CloudFront URL: https://${CF_DOMAIN}/"
echo "   Grafana admin: skills${BIBUN} / HelloKrSkills!${BIBUN}@"
