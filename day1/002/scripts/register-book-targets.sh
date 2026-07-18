#!/bin/bash
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/root/.kube/wskorea26.yaml}"
BOOK_TG=$(aws elbv2 describe-target-groups --names wskorea26-book-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
EXISTING=$(aws elbv2 describe-target-health --target-group-arn "$BOOK_TG" --query 'TargetHealthDescriptions[].Target.Id' --output text)
for id in $EXISTING; do
  [[ -n "$id" && "$id" != "None" ]] && aws elbv2 deregister-targets --target-group-arn "$BOOK_TG" --targets Id=$id,Port=8080 || true
done
for ip in $(kubectl -n wskorea26 get pods -l app=book -o jsonpath='{.items[*].status.podIP}'); do
  aws elbv2 register-targets --target-group-arn "$BOOK_TG" --targets Id=$ip,Port=8080
done
aws elbv2 describe-target-health --target-group-arn "$BOOK_TG" --output table
