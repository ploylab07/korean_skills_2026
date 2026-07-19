#!/usr/bin/env bash
# Rename EKS Bottlerocket nodes to gj2026.<instance-id>.{addon|app}.node
set -euo pipefail
export AWS_DEFAULT_REGION=ap-northeast-2
CLUSTER=gj2026-eks-cluster
aws eks update-kubeconfig --name "$CLUSTER" --region ap-northeast-2 >/dev/null

# Get instances for each nodegroup via ASG tags
fix_nodes() {
  local role=$1  # addon|app
  local instances
  instances=$(aws ec2 describe-instances \
    --filters "Name=tag:eks:nodegroup-name,Values=gj2026-eks-${role}-nodegroup" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)

  for iid in $instances; do
    desired="gj2026.${iid}.${role}.node"
    current=$(kubectl get nodes -o json | jq -r --arg iid "$iid" '
      .items[] | select(.spec.providerID | endswith("/"+$iid)) | .metadata.name' | head -1)
    echo "instance=$iid current=$current desired=$desired"
    if [[ -n "$current" && "$current" != "$desired" ]]; then
      # Bottlerocket: set via SSM if agent present, else recreate later
      # Use kubectl label + cordon approach won't rename. Use AWS Systems Manager:
      aws ssm send-command \
        --instance-ids "$iid" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"apiclient set settings.kubernetes.node-name=${desired} || true\",\"apiclient set settings.network.hostname=${desired} || true\"]" \
        --timeout-seconds 60 >/dev/null 2>&1 || echo "SSM not available for $iid"
    fi
  done
}

fix_nodes addon
fix_nodes app

echo "Waiting 60s for kubelet re-register..."
sleep 60
kubectl get nodes -o wide || true
