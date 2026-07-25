#!/bin/bash
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
CLUSTER="${CLUSTER_NAME:-wskorea26-cluster}"
aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name "$CLUSTER" --alias wskorea26 --kubeconfig "${KUBECONFIG:-$HOME/.kube/wskorea26.yaml}" >/dev/null
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/wskorea26.yaml}"

BOOK_TG=$(aws elbv2 describe-target-groups --names wskorea26-book-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
EXISTING=$(aws elbv2 describe-target-health --target-group-arn "$BOOK_TG" --query 'TargetHealthDescriptions[].Target.Id' --output text || true)
for id in $EXISTING; do
  [[ -n "$id" && "$id" != "None" ]] && aws elbv2 deregister-targets --target-group-arn "$BOOK_TG" --targets Id=$id,Port=8080 || true
done
for ip in $(kubectl --context wskorea26 -n wskorea26 get pods -l app=book -o jsonpath='{.items[*].status.podIP}'); do
  [[ -n "$ip" ]] && aws elbv2 register-targets --target-group-arn "$BOOK_TG" --targets Id=$ip,Port=8080
done

# Grafana
if aws elbv2 describe-target-groups --names wskorea26-grafana-tg >/dev/null 2>&1; then
  GTG=$(aws elbv2 describe-target-groups --names wskorea26-grafana-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
  GEXIST=$(aws elbv2 describe-target-health --target-group-arn "$GTG" --query 'TargetHealthDescriptions[].Target.Id' --output text || true)
  for id in $GEXIST; do
    [[ -n "$id" && "$id" != "None" ]] && aws elbv2 deregister-targets --target-group-arn "$GTG" --targets Id=$id,Port=3000 || true
  done
  GIP=$(kubectl --context wskorea26 -n monitoring get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
  [[ -n "$GIP" ]] && aws elbv2 register-targets --target-group-arn "$GTG" --targets Id=$GIP,Port=3000
fi

aws elbv2 describe-target-health --target-group-arn "$BOOK_TG" --output table
