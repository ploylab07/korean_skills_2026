#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_DIR="${ROOT_DIR}"
REPO_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/.env"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
ACCOUNT_ID="163389715563"
CLUSTER_NAME="wsc2026-eks-cluster"
ECR_REPO="wsc2026-book-ecr"
IMAGE_TAG="v1.0.0"

log() { echo "[deploy] $*"; }

run_terraform() {
  "${REPO_ROOT}/terraform" -chdir="${MODULE_DIR}" "$@"
}

log "Initializing Terraform"
run_terraform init -input=false

log "Applying network + KMS first"
run_terraform apply -input=false -auto-approve \
  -target=aws_vpc.main \
  -target=aws_internet_gateway.main \
  -target=aws_subnet.hub_a \
  -target=aws_subnet.hub_b \
  -target=aws_subnet.app_a \
  -target=aws_subnet.app_b \
  -target=aws_eip.nat_a \
  -target=aws_eip.nat_b \
  -target=aws_nat_gateway.nat_a \
  -target=aws_nat_gateway.nat_b \
  -target=aws_route_table.hub \
  -target=aws_route_table.app_a \
  -target=aws_route_table.app_b \
  -target=aws_route_table_association.hub_a \
  -target=aws_route_table_association.hub_b \
  -target=aws_route_table_association.app_a \
  -target=aws_route_table_association.app_b \
  -target=aws_security_group.mark \
  -target=aws_security_group.alb \
  -target=aws_security_group.eks_cluster \
  -target=aws_security_group.eks_nodes \
  -target=aws_security_group.bastion \
  -target=aws_security_group_rule.cluster_from_bastion \
  -target=aws_security_group_rule.cluster_from_nodes \
  -target=aws_iam_role.kms_admin \
  -target=aws_iam_role.book_pod \
  -target=aws_iam_role.book_function \
  -target=aws_kms_key.db \
  -target=aws_kms_alias.db \
  -target=aws_kms_key.ecr \
  -target=aws_kms_alias.ecr \
  -target=aws_kms_key.eks \
  -target=aws_kms_alias.eks \
  -target=aws_kms_key.bucket \
  -target=aws_kms_alias.bucket \
  -target=aws_kms_key.function \
  -target=aws_kms_alias.function || true

log "Applying full Terraform stack"
run_terraform apply -input=false -auto-approve

log "Setting DynamoDB PITR retention to 35 days"
aws dynamodb update-continuous-backups \
  --table-name wsc2026-book-table \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true,RecoveryPeriodInDays=35 \
  --region "${AWS_DEFAULT_REGION}" || true

log "Building and pushing container image ${IMAGE_TAG}"
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REPO}"
aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
docker build -t "${ECR_URL}:${IMAGE_TAG}" "${MODULE_DIR}"
docker push "${ECR_URL}:${IMAGE_TAG}"

BASTION_ID=$(run_terraform output -raw bastion_instance_id)
ALB_SG=$(run_terraform output -raw alb_sg_id)
HUB_SUBNETS=$(run_terraform output -json hub_subnet_ids | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)))')
VPC_ID=$(run_terraform output -raw vpc_id)
ALB_CONTROLLER_ROLE="arn:aws:iam::${ACCOUNT_ID}:role/wsc2026-alb-controller-role"

log "Configuring kubeconfig via bastion SSM (${BASTION_ID})"
KUBECONFIG_CMD="aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_DEFAULT_REGION}"

TMP_K8S=$(mktemp -d)
trap 'rm -rf "${TMP_K8S}"' EXIT

cp "${MODULE_DIR}/k8s/observability.yaml" "${TMP_K8S}/observability.yaml"

sed "s|PLACEHOLDER_ECR_IMAGE|${ECR_URL}:${IMAGE_TAG}|g" \
  "${MODULE_DIR}/k8s/book-app.yaml" > "${TMP_K8S}/book-app.yaml"
sed "s|PLACEHOLDER_ALB_SG|${ALB_SG}|g; s|PLACEHOLDER_HUB_SUBNETS|${HUB_SUBNETS}|g" \
  "${TMP_K8S}/book-app.yaml" > "${TMP_K8S}/book-app-final.yaml"
mv "${TMP_K8S}/book-app-final.yaml" "${TMP_K8S}/book-app.yaml"

sed "s|PLACEHOLDER_VPC_ID|${VPC_ID}|g" \
  "${MODULE_DIR}/k8s/alb-controller.yaml" > "${TMP_K8S}/alb-controller.yaml"

cat > "${TMP_K8S}/alb-controller-patch.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${ALB_CONTROLLER_ROLE}
EOF

apply_via_bastion() {
  local manifest_dir="$1"
  tar czf /tmp/k8s-manifests.tgz -C "${manifest_dir}" .
  B64=$(base64 -w0 /tmp/k8s-manifests.tgz)

  aws ssm send-command \
    --instance-ids "${BASTION_ID}" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="[
      \"set -e\",
      \"mkdir -p /tmp/k8s-deploy\",
      \"echo ${B64} | base64 -d > /tmp/k8s-manifests.tgz\",
      \"tar xzf /tmp/k8s-manifests.tgz -C /tmp/k8s-deploy\",
      \"${KUBECONFIG_CMD}\",
      \"kubectl apply -f /tmp/k8s-deploy/alb-controller-patch.yaml\",
      \"kubectl apply -f /tmp/k8s-deploy/alb-controller.yaml\",
      \"kubectl apply -f /tmp/k8s-deploy/book-app.yaml\",
      \"kubectl apply -f /tmp/k8s-deploy/observability.yaml\",
      \"kubectl -n wsc2026 rollout status deploy/wsc2026-book-deploy --timeout=600s\"
    ]" \
    --query 'Command.CommandId' --output text
}

CMD_ID=$(apply_via_bastion "${TMP_K8S}")
log "Waiting for SSM command ${CMD_ID}"
for i in $(seq 1 60); do
  STATUS=$(aws ssm get-command-invocation --command-id "${CMD_ID}" --instance-id "${BASTION_ID}" --query Status --output text 2>/dev/null || echo Pending)
  if [[ "${STATUS}" == "Success" ]]; then
    log "Kubernetes deployment completed"
    break
  elif [[ "${STATUS}" == "Failed" ]]; then
    aws ssm get-command-invocation --command-id "${CMD_ID}" --instance-id "${BASTION_ID}" --query StandardErrorContent --output text || true
    log "SSM command failed - try manual kubectl from bastion"
    break
  fi
  sleep 10
done

log "Deployment finished"
run_terraform output
