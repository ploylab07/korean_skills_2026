#!/usr/bin/env bash
# EKS 클러스터 준비 후 Helm/Kubectl 리소스 배포
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
CLUSTER="gj2025-eks-cluster"

source "$ROOT/build/load-env.sh"
load_repo_env "$ROOT/build"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

wait_eks() {
  log "EKS 클러스터 ACTIVE 대기"
  aws eks wait cluster-active --name "$CLUSTER" --region "$REGION"
  aws eks wait nodegroup-active --cluster-name "$CLUSTER" --nodegroup-name gj2025-eks-addon-nodegroup --region "$REGION"
  aws eks wait nodegroup-active --cluster-name "$CLUSTER" --nodegroup-name gj2025-eks-app-nodegroup --region "$REGION"
}

setup_kubeconfig() {
  if ! aws --version 2>&1 | grep -q 'aws-cli/2'; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --update -i /usr/local/aws-cli -b /usr/local/bin
  fi
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --alias gj2025
}

read_tf() {
  ECR_RED=$("$TF" -chdir="$DIR" output -raw ecr_red_url)
  ECR_GREEN=$("$TF" -chdir="$DIR" output -raw ecr_green_url)
  TG_RED=$("$TF" -chdir="$DIR" output -raw tg_red_arn)
  TG_GREEN=$("$TF" -chdir="$DIR" output -raw tg_green_arn)
  TG_ARGO=$("$TF" -chdir="$DIR" output -raw tg_argo_arn)
  EXT_SECRETS_ROLE=$("$TF" -chdir="$DIR" output -raw external_secrets_role_arn)
  FLUENT_BIT_ROLE=$("$TF" -chdir="$DIR" output -raw fluent_bit_role_arn)
  LB_CTRL_ROLE=$("$TF" -chdir="$DIR" output -raw lb_controller_role_arn)
  APP_VPC=$("$TF" -chdir="$DIR" output -raw app_vpc_id)
  DB_SECRET_NAME=$("$TF" -chdir="$DIR" output -raw db_catalog_secret_name)
  ECR_REGISTRY="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com"
}

install_helm_charts() {
  local HELM_WAIT="--timeout 10m --wait"

  log "AWS Load Balancer Controller"
  helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system --create-namespace \
    --set clusterName="$CLUSTER" \
    --set region="$REGION" \
    --set vpcId="$APP_VPC" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${LB_CTRL_ROLE}" \
    --set nodeSelector.role=addon \
    --set "image.repository=${ECR_REGISTRY}/addon/aws-lb-controller" \
    --set image.tag=v2.17.1 \
    --version 1.17.1 $HELM_WAIT

  log "Secrets Store CSI Driver"
  helm uninstall secrets-store-csi-driver -n kube-system 2>/dev/null || true
  kubectl delete job -n kube-system -l app=secrets-store-csi-driver-upgrade-crds 2>/dev/null || true
  helm upgrade --install secrets-store-csi-driver \
    secrets-store-csi-driver/secrets-store-csi-driver \
    --namespace kube-system \
    --set syncSecret.enabled=true \
    --set enableSecretRotation=true \
    --set nodeSelector.role=addon \
    --set "linux.image.repository=${ECR_REGISTRY}/addon/secrets-store-csi" \
    --set linux.image.tag=v1.4.6 \
    --set "linux.registrarImage.repository=${ECR_REGISTRY}/addon/csi-node-driver-registrar" \
    --set linux.registrarImage.tag=v2.13.0 \
    --set "linux.livenessProbeImage.repository=${ECR_REGISTRY}/addon/livenessprobe" \
    --set linux.livenessProbeImage.tag=v2.15.0 \
    --set "linux.crds.image.repository=${ECR_REGISTRY}/addon/driver-crds" \
    --set linux.crds.image.tag=v1.4.6 \
    --version 1.4.6 $HELM_WAIT

  log "External Secrets Operator"
  helm uninstall external-secrets -n external-secrets 2>/dev/null || true
  helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets --create-namespace \
    --set installCRDs=true \
    --set nodeSelector.role=addon \
    --set "image.repository=${ECR_REGISTRY}/addon/external-secrets" \
    --set image.tag=v0.9.19 \
    --set "webhook.image.repository=${ECR_REGISTRY}/addon/external-secrets" \
    --set webhook.image.tag=v0.9.19 \
    --set "certController.image.repository=${ECR_REGISTRY}/addon/external-secrets" \
    --set certController.image.tag=v0.9.19 \
    --version 0.9.19 $HELM_WAIT

  log "Argo Rollouts"
  helm upgrade --install argo-rollouts argo/argo-rollouts \
    --namespace argo-rollouts --create-namespace \
    --set controller.nodeSelector.role=addon \
    --set "controller.image.registry=${ECR_REGISTRY}" \
    --set controller.image.repository=addon/argo-rollouts \
    --set controller.image.tag=v1.7.2 \
    --version 2.37.7 $HELM_WAIT

  log "ArgoCD"
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --create-namespace \
    --set global.nodeSelector.role=addon \
    --set "global.image.repository=${ECR_REGISTRY}/addon/argocd" \
    --set global.image.tag=v2.13.2 \
    --set configs.secret.argocdServerAdminPassword='$2b$12$fERBUGzfQK25FwPuLug/8.xebOg5bdq7uZYCFLDdTOPCLZa0f0oje' \
    --set server.service.type=ClusterIP \
    --set server.extraArgs[0]=--insecure \
    --version 7.7.10 $HELM_WAIT
}

apply_manifests() {
  log "Kubernetes 매니페스트 적용"
  export ECR_RED ECR_GREEN TG_RED TG_GREEN TG_ARGO EXT_SECRETS_ROLE FLUENT_BIT_ROLE REGION DB_SECRET_NAME ECR_REGISTRY
  export GITHUB_OWNER=$("$TF" -chdir="$DIR" output -json 2>/dev/null | jq -r .github_owner.value 2>/dev/null || echo "jeonghee-seock")
  GITHUB_OWNER=$(grep github_owner "${DIR}/terraform.tfvars" | awk -F'"' '{print $2}')
  GITHUB_REPO=$(grep github_repo "${DIR}/terraform.tfvars" | awk -F'"' '{print $2}')
  export GITHUB_OWNER GITHUB_REPO
  export IMAGE_RED="${ECR_RED}:latest"
  export IMAGE_GREEN="${ECR_GREEN}:latest"

  envsubst < "${DIR}/manifests/k8s-base.yaml.tpl" | kubectl apply -f -
  envsubst < "${DIR}/manifests/red-rollout.yaml.tpl" | kubectl apply -f -
  envsubst < "${DIR}/manifests/green-rollout.yaml.tpl" | kubectl apply -f -
  envsubst < "${DIR}/manifests/fluent-bit-red.yaml.tpl" | kubectl apply -f -
  envsubst < "${DIR}/manifests/fluent-bit-green.yaml.tpl" | kubectl apply -f -
  envsubst < "${DIR}/manifests/argocd-apps.yaml.tpl" | kubectl apply -f -
}

wait_workloads() {
  log "워크로드 준비 대기"
  kubectl -n skills wait --for=condition=available --timeout=600s deployment -l app 2>/dev/null || true
  kubectl -n skills get rollout red-rollout green-rollout 2>/dev/null || true
  for i in $(seq 1 60); do
    if kubectl -n skills get externalsecret db-secret -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; then
      log "ExternalSecret 동기화 완료"
      break
    fi
    sleep 10
  done
}

main() {
  wait_eks
  setup_kubeconfig
  read_tf
  helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
  helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts 2>/dev/null || true
  helm repo update
  install_helm_charts
  apply_manifests
  wait_workloads
  log "K8s 배포 완료"
}

main "$@"
