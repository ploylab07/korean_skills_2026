#!/usr/bin/env bash
# Registers Book App / Grafana pod IPs into their ALB target groups (IP mode).
# Used instead of the AWS Load Balancer Controller for simplicity/reliability.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
CLUSTER="${CLUSTER_NAME:-unicorn-eks-cluster}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/unicorn.yaml}"
export KUBECONFIG

aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name "$CLUSTER" --alias unicorn --kubeconfig "$KUBECONFIG" >/dev/null

sync_target_group() {
  local tg_name="$1" port="$2" namespace="$3" selector="$4"

  local tg_arn
  tg_arn=$(aws elbv2 describe-target-groups --names "$tg_name" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null) || return 0
  [[ -z "$tg_arn" || "$tg_arn" == "None" ]] && return 0

  local existing
  existing=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" --query 'TargetHealthDescriptions[].Target.Id' --output text 2>/dev/null || true)
  for id in $existing; do
    [[ -n "$id" && "$id" != "None" ]] && aws elbv2 deregister-targets --target-group-arn "$tg_arn" --targets "Id=$id,Port=$port" || true
  done

  local ips
  ips=$(kubectl --context unicorn -n "$namespace" get pods -l "$selector" -o jsonpath='{.items[*].status.podIP}' 2>/dev/null || true)
  for ip in $ips; do
    [[ -n "$ip" ]] && aws elbv2 register-targets --target-group-arn "$tg_arn" --targets "Id=$ip,Port=$port"
  done

  echo "== $tg_name =="
  aws elbv2 describe-target-health --target-group-arn "$tg_arn" --output table || true
}

sync_target_group "unicorn-tg" 8080 unicorn "app=book"
sync_target_group "unicorn-grafana-tg" 3000 monitoring "app.kubernetes.io/name=grafana"
