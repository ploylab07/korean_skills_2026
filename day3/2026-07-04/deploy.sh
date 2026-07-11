#!/usr/bin/env bash
# WSC 2026 제2과제 — Terraform apply / post-deploy / destroy
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$ROOT/terraform"
MANIFESTS="$DIR/manifests"

source "$ROOT/build/load-env.sh"
load_repo_env "$ROOT/build"

ACTION="${1:-apply}"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

wait_eks() {
  local region="$1" cluster="$2" ng="$3"
  log "EKS 대기: $cluster ($region)"
  aws eks wait cluster-active --name "$cluster" --region "$region"
  aws eks wait nodegroup-active --cluster-name "$cluster" --nodegroup-name "$ng" --region "$region"
}

install_kubectl_helm() {
  if ! command -v kubectl >/dev/null 2>&1; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  fi
  if ! command -v helm >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
}

post_scaling() {
  wait_eks ap-northeast-2 wsc-scaling-cluster wsc-scaling-node
  aws eks update-kubeconfig --region ap-northeast-2 --name wsc-scaling-cluster

  SQS_URL=$("$TF" -chdir="$DIR" output -raw scaling_sqs_url)
  KARPENTER_ROLE=$("$TF" -chdir="$DIR" output -raw scaling_karpenter_role)
  export sqs_url="$SQS_URL" karpenter_node_role="$KARPENTER_ROLE"
  envsubst '$sqs_url $karpenter_node_role' < "$MANIFESTS/scaling-extra.yaml.tpl" | kubectl apply -f -

  log "Scaling 리소스 확인"
  kubectl get ns wsc-scaling
  kubectl get deployment,scaledobject -n wsc-scaling
}

pre_destroy() {
  install_kubectl_helm
  log "EKS/K8s 사전 정리"

  if aws eks describe-cluster --name wsc-scaling-cluster --region ap-northeast-2 &>/dev/null; then
    aws eks update-kubeconfig --region ap-northeast-2 --name wsc-scaling-cluster
    kubectl delete scaledobject,triggerauthentication -n wsc-scaling --all --ignore-not-found --wait=false 2>/dev/null || true
    kubectl patch scaledobject -n wsc-scaling --all -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
    kubectl delete nodepool,ec2nodeclass --all --ignore-not-found --wait=false 2>/dev/null || true
    kubectl delete ns wsc-scaling keda --ignore-not-found --wait=false 2>/dev/null || true
    for ns in wsc-scaling keda; do
      kubectl get ns "$ns" -o json 2>/dev/null \
        | python3 -c "import json,sys; d=json.load(sys.stdin); d['spec']['finalizers']=[]; print(json.dumps(d))" \
        | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - 2>/dev/null || true
    done
    helm uninstall karpenter -n kube-system 2>/dev/null || true
    helm uninstall keda -n keda 2>/dev/null || true
  fi

  if aws eks describe-cluster --name wsc-logging-cluster --region ap-northeast-1 &>/dev/null; then
    aws eks update-kubeconfig --region ap-northeast-1 --name wsc-logging-cluster
    helm uninstall grafana loki -n wsc-logging 2>/dev/null || true
    kubectl delete ns wsc-logging --ignore-not-found --wait=false 2>/dev/null || true
  fi
}

post_logging() {
  wait_eks ap-northeast-1 wsc-logging-cluster wsc-logging-ng
  aws eks update-kubeconfig --region ap-northeast-1 --name wsc-logging-cluster

  log "Loki NLB 대기"
  LOKI=""
  for i in $(seq 1 60); do
    LOKI=$(kubectl get svc -n wsc-logging -l app.kubernetes.io/name=loki \
      -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [[ -n "$LOKI" && "$LOKI" != "null" ]]; then break; fi
    sleep 15
  done

  if [[ -z "$LOKI" || "$LOKI" == "null" ]]; then
    log "Loki NLB 미확인 — Fluent Bit 수동 설정 필요"
    return 0
  fi

  log "Loki: $LOKI"
  INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
    --filters "Name=tag:Name,Values=wsc-log-app-bastion" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)

  [[ "$INSTANCE_ID" == "None" || -z "$INSTANCE_ID" ]] && return 0

  CMD_ID=$(aws ssm send-command --region ap-northeast-1 --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"sed -i 's|Host.*|Host          $LOKI|' /etc/fluent-bit/fluent-bit.conf\", \"systemctl restart fluent-bit\"]" \
    --query Command.CommandId --output text)
  sleep 8
  aws ssm get-command-invocation --region ap-northeast-1 --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" --query StandardOutputContent --output text || true
}

case "$ACTION" in
  init)
    "$TF" -chdir="$DIR" init -upgrade
    ;;
  plan)
    "$TF" -chdir="$DIR" plan
    ;;
  apply)
    install_kubectl_helm
    "$TF" -chdir="$DIR" init -upgrade
    "$TF" -chdir="$DIR" apply -auto-approve
    post_scaling
    post_logging
    ;;
  post)
    install_kubectl_helm
    post_scaling
    post_logging
    ;;
  destroy)
    pre_destroy || true
    "$TF" -chdir="$DIR" destroy -auto-approve -lock=false
    ;;
  validate)
    "$TF" -chdir="$DIR" init -upgrade -input=false
    "$TF" -chdir="$DIR" validate
    ;;
  *)
    echo "Usage: $0 {init|plan|apply|post|destroy|validate}"
    exit 1
    ;;
esac
