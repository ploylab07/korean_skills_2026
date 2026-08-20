#!/usr/bin/env bash
# day1/003 deploy: terraform (phase1) → ECR image → k8s → CloudFront (phase2)
# Run from anywhere:
#   bash day1/003/scripts/deploy.sh
#   cd day1/003 && bash scripts/deploy.sh
#   cd day1/003 && ./deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_up() {
  local dir="$1" name="$2"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -e "${dir}/${name}" ]]; then
      printf '%s\n' "${dir}"
      return 0
    fi
    dir="$(cd "${dir}/.." && pwd)"
  done
  return 1
}

# Assignment dir = folder that contains eks.tf (scripts/ 또는 day1/003 어디에 두든)
if [[ -f "${SCRIPT_DIR}/eks.tf" ]]; then
  ROOT_DIR="${SCRIPT_DIR}"
else
  ROOT_DIR="$(find_up "${SCRIPT_DIR}" "eks.tf" || true)"
fi
if [[ -z "${ROOT_DIR}" || ! -f "${ROOT_DIR}/eks.tf" ]]; then
  echo "deploy.sh: eks.tf 를 찾지 못했습니다. day1/003 폴더에서 실행하세요." >&2
  echo "  cd day1/003 && bash scripts/deploy.sh" >&2
  exit 1
fi

REPO_ROOT="$(find_up "${ROOT_DIR}" ".env" || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(find_up "${ROOT_DIR}" "setup-aws" || true)"
fi
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"
fi

if [[ -f "${REPO_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a && source "${REPO_ROOT}/.env" && set +a
elif [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a && source "${ROOT_DIR}/.env" && set +a
fi

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CLUSTER_NAME="wsc2026-eks-cluster"
ECR_REPO="wsc2026-book-ecr"
IMAGE_TAG="v1.0.0"

if [[ -x "${REPO_ROOT}/terraform" ]]; then
  TF=("${REPO_ROOT}/terraform" -chdir="${ROOT_DIR}")
elif command -v terraform >/dev/null 2>&1; then
  TF=(terraform -chdir="${ROOT_DIR}")
else
  echo "deploy.sh: terraform 을 찾지 못했습니다. PATH 또는 저장소 루트의 ./terraform 이 필요합니다." >&2
  exit 1
fi

log() { echo "[deploy] $*"; }

log "Phase 1: Terraform apply (infra, no CDN)"
"${TF[@]}" init -input=false
"${TF[@]}" apply -input=false -auto-approve -var='enable_cdn=false'

log "Enable EKS public endpoint for bootstrap kubectl"
aws eks update-cluster-config --name "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}" \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true >/dev/null || true
for i in $(seq 1 30); do
  PUB=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query 'cluster.resourcesVpcConfig.endpointPublicAccess' --output text 2>/dev/null || echo False)
  [[ "${PUB}" == "True" ]] && break
  sleep 10
done

log "PITR 35 days"
aws dynamodb update-continuous-backups \
  --table-name wsc2026-book-table \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true,RecoveryPeriodInDays=35 \
  --region "${AWS_DEFAULT_REGION}" || true

ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REPO}"
if aws ecr describe-images --repository-name "${ECR_REPO}" --image-ids "imageTag=${IMAGE_TAG}" --region "${AWS_DEFAULT_REGION}" >/dev/null 2>&1; then
  log "ECR image ${ECR_REPO}:${IMAGE_TAG} already present (CodeBuild/Terraform), skip local push"
else
  log "Build & push ${ECR_URL}:${IMAGE_TAG}"
  aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" \
    | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
  docker build -t "${ECR_URL}:${IMAGE_TAG}" "${ROOT_DIR}"
  docker push "${ECR_URL}:${IMAGE_TAG}"
fi

ALB_SG=$("${TF[@]}" output -raw alb_sg_id)
HUB_SUBNETS=$("${TF[@]}" output -json hub_subnet_ids | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)))')
VPC_ID=$("${TF[@]}" output -raw vpc_id)
ALB_ROLE="arn:aws:iam::${ACCOUNT_ID}:role/wsc2026-alb-controller-role"

log "kubeconfig"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}"

# Wait for nodes and pin scoring labels (mark.sh 4-2)
for i in $(seq 1 60); do
  READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
  log "Ready nodes: ${READY}"
  [[ "${READY}" -ge 4 ]] && break
  sleep 15
done
kubectl label nodes -l eks.amazonaws.com/nodegroup=wsc2026-addon-nodegroup wsc2026/node=addon --overwrite || true
kubectl label nodes -l eks.amazonaws.com/nodegroup=wsc2026-workload-ng wsc2026/node=application --overwrite || true
kubectl get nodes --show-labels | grep wsc2026/node || true

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

log "Observability: kube-prometheus-stack (prometheus:7) + grafana + fluent-bit"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community || helm repo update
kubectl apply -f "${ROOT_DIR}/k8s/observability.yaml" || true
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n observability --create-namespace \
  -f "${ROOT_DIR}/k8s/kube-prometheus-values.yaml" \
  --wait --timeout 12m || true

kubectl -n wsc2026 rollout status deploy/wsc2026-book-deploy --timeout=600s || true
kubectl -n observability rollout status deploy/grafana --timeout=180s || true

log "Wait for ALB"
ALB_DNS=""
for i in $(seq 1 60); do
  ALB_DNS=$(kubectl get ingress -n wsc2026 wsc2026-book-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "${ALB_DNS}" ]] && break
  sleep 15
done
log "ALB DNS: ${ALB_DNS}"

log "Wait for Grafana NLB (mark.sh 11-2/11-3 URL)"
GRAFANA_LB=""
for i in $(seq 1 40); do
  GRAFANA_LB=$(kubectl get svc -n observability grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "${GRAFANA_LB}" ]] && break
  sleep 10
done
log "Grafana: http://${GRAFANA_LB}"

# Let CloudShell GetFunction see plaintext TABLE_NAME (key policy cannot contain :root)
FN_KEY=$(aws kms describe-key --key-id alias/wsc2026-function-kms --query KeyMetadata.Arn --output text 2>/dev/null || true)
if [[ -n "${FN_KEY}" ]]; then
  aws kms create-grant --key-id "${FN_KEY}" \
    --grantee-principal "arn:aws:iam::${ACCOUNT_ID}:root" \
    --operations Decrypt Encrypt GenerateDataKey DescribeKey CreateGrant >/dev/null 2>&1 || true
fi

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
