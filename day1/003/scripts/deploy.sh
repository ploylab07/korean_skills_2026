#!/usr/bin/env bash
# day1/003 deploy: terraform (phase1) → ECR image → k8s → CloudFront (phase2)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
set -a && source "${REPO_ROOT}/.env" && set +a

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CLUSTER_NAME="wsc2026-eks-cluster"
ECR_REPO="wsc2026-book-ecr"
IMAGE_TAG="v1.0.0"
TF=("${REPO_ROOT}/terraform" -chdir="${ROOT_DIR}")

log() { echo "[deploy] $*"; }

log "Phase 1: Terraform apply (infra, no CDN)"
"${TF[@]}" init -input=false
"${TF[@]}" apply -input=false -auto-approve -var='enable_cdn=false'

log "PITR 35 days"
aws dynamodb update-continuous-backups \
  --table-name wsc2026-book-table \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true,RecoveryPeriodInDays=35 \
  --region "${AWS_DEFAULT_REGION}" || true

ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REPO}"
log "Build & push ${ECR_URL}:${IMAGE_TAG}"
aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
docker build -t "${ECR_URL}:${IMAGE_TAG}" "${ROOT_DIR}"
docker push "${ECR_URL}:${IMAGE_TAG}"

ALB_SG=$("${TF[@]}" output -raw alb_sg_id)
HUB_SUBNETS=$("${TF[@]}" output -json hub_subnet_ids | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)))')
VPC_ID=$("${TF[@]}" output -raw vpc_id)
ALB_ROLE="arn:aws:iam::${ACCOUNT_ID}:role/wsc2026-alb-controller-role"

log "kubeconfig"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}"

# Wait for nodes
for i in $(seq 1 60); do
  READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
  log "Ready nodes: ${READY}"
  [[ "${READY}" -ge 2 ]] && break
  sleep 15
done

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

sed "s|PLACEHOLDER_ECR_IMAGE|${ECR_URL}:${IMAGE_TAG}|g; s|PLACEHOLDER_ALB_SG|${ALB_SG}|g; s|PLACEHOLDER_HUB_SUBNETS|${HUB_SUBNETS}|g" \
  "${ROOT_DIR}/k8s/book-app.yaml" > "${TMP}/book-app.yaml"
sed "s|PLACEHOLDER_VPC_ID|${VPC_ID}|g" \
  "${ROOT_DIR}/k8s/alb-controller.yaml" > "${TMP}/alb-controller.yaml"

# Install AWS LB Controller via helm if available, else raw manifests
if command -v helm >/dev/null 2>&1; then
  helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
  helm repo update
  kubectl create sa aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl annotate sa aws-load-balancer-controller -n kube-system \
    eks.amazonaws.com/role-arn="${ALB_ROLE}" --overwrite
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="${CLUSTER_NAME}" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region="${AWS_DEFAULT_REGION}" \
    --set vpcId="${VPC_ID}" \
    --wait --timeout 10m || true
else
  kubectl apply -f "${TMP}/alb-controller.yaml" || true
fi

kubectl apply -f "${TMP}/book-app.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/observability.yaml" || true

kubectl -n wsc2026 rollout status deploy/wsc2026-book-deploy --timeout=600s || true

log "Wait for ALB"
ALB_DNS=""
for i in $(seq 1 60); do
  ALB_DNS=$(kubectl get ingress -n wsc2026 wsc2026-book-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "${ALB_DNS}" ]] && break
  sleep 15
done
log "ALB DNS: ${ALB_DNS}"

if [[ -n "${ALB_DNS}" ]]; then
  log "Phase 2: CloudFront + WAF"
  "${TF[@]}" apply -input=false -auto-approve \
    -var='enable_cdn=true' \
    -var="alb_dns_name=${ALB_DNS}"
fi

# Final: private-only EKS endpoint for mark.sh
log "Set EKS endpoint publicAccess=false"
aws eks update-cluster-config --name "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}" \
  --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true || true

log "Done"
"${TF[@]}" output
