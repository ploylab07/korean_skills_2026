#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER="${EKS_CLUSTER_NAME:-wsc-eks-cluster}"

log() { echo "[post-deploy] $*"; }

export AWS_DEFAULT_REGION="$REGION"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

TF_OUT() { terraform -chdir="$DIR" output -raw "$1" 2>/dev/null || true; }

export REGION="$REGION"
export KMS_KEY_ARN="$(TF_OUT kms_key_arn)"
export TABLE_NAME="$(TF_OUT dynamodb_table_name)"
export ECR_IMAGE="$(TF_OUT ecr_repository_url):v1.0.0"
export APP_POD_ROLE_ARN="$(TF_OUT app_pod_role_arn)"
export FLUENT_BIT_ROLE_ARN="$(TF_OUT fluent_bit_role_arn)"
export LOG_GROUP="$(TF_OUT log_group_name)"
export APP_TG_ARN="$(TF_OUT app_target_group_arn)"
export GRAFANA_TG_ARN="$(TF_OUT grafana_target_group_arn)"
export PROM_TG_ARN="$(TF_OUT prometheus_target_group_arn)"
export LB_CONTROLLER_ROLE="$(TF_OUT lb_controller_role_arn)"
export VPC_ID="$(TF_OUT vpc_id)"

install_tools() {
  command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo update
}

install_lb_controller() {
  log "AWS Load Balancer Controller"
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system --create-namespace \
    --set clusterName="$CLUSTER" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$LB_CONTROLLER_ROLE" \
    --set region="$REGION" \
    --set vpcId="$VPC_ID" \
    --set nodeSelector.type=addon \
    --set "tolerations[0].key=type" \
    --set "tolerations[0].value=addon" \
    --set "tolerations[0].effect=NoSchedule"
}

install_monitoring() {
  log "Prometheus + Grafana"
  helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.nodeSelector.type=monitoring \
    --set "prometheus.prometheusSpec.tolerations[0].key=type" \
    --set "prometheus.prometheusSpec.tolerations[0].value=monitoring" \
    --set "prometheus.prometheusSpec.tolerations[0].effect=NoSchedule" \
    --set grafana.nodeSelector.type=monitoring \
    --set "grafana.tolerations[0].key=type" \
    --set "grafana.tolerations[0].value=monitoring" \
    --set "grafana.tolerations[0].effect=NoSchedule" \
    --set grafana.adminPassword='Skill53##' \
    --set grafana.persistence.enabled=true \
    --set grafana.persistence.storageClassName=wsc-sc \
    --set grafana.persistence.size=10Gi \
    --set grafana.ingress.enabled=false \
    --set "grafana.datasources.datasources\\.yaml.apiVersion=1" \
    --set "grafana.datasources.datasources\\.yaml.datasources[0].name=Prometheus" \
    --set "grafana.datasources.datasources\\.yaml.datasources[0].type=prometheus" \
    --set "grafana.datasources.datasources\\.yaml.datasources[0].url=http://prometheus-server.monitoring.svc.wsc.local/prometheus" \
    --set "grafana.datasources.datasources\\.yaml.datasources[0].isDefault=true"
}

apply_manifests() {
  log "Kubernetes manifests"
  envsubst < "$DIR/manifests/k8s-base.yaml.tpl" | kubectl apply -f -
  envsubst < "$DIR/manifests/wsc-deploy.yaml.tpl" | kubectl apply -f -
  envsubst < "$DIR/manifests/fluent-bit.yaml.tpl" | kubectl apply -f -
  envsubst < "$DIR/manifests/monitoring-tgb.yaml.tpl" | kubectl apply -f -
}

install_tools
install_lb_controller
sleep 20
apply_manifests
install_monitoring

kubectl -n wsc rollout status deployment/wsc-deploy --timeout=600s || true
log "Done"
