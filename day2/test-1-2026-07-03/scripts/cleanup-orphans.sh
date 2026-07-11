#!/usr/bin/env bash
# 고아/실패 wsc 리소스 정리 (Terraform state 밖·실패 ASG·남은 EC2 등)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
CLUSTER="wsc-eks-cluster"
PREFIX="wsc"

# shellcheck source=/dev/null
source "$ROOT/build/load-env.sh"
load_repo_env "$ROOT/build"

export AWS_DEFAULT_REGION="$REGION"

log() { echo "[cleanup] $*"; }
die() { echo "[cleanup] ERROR: $*" >&2; exit 1; }

aws sts get-caller-identity >/dev/null || die "AWS 인증 실패 — .env 키를 갱신하세요 (./setup-aws)"

log "=== 1. 실패/유령 EKS NodeGroup 삭제 ==="
for ng in wsc-app-ng wsc-addon-ng wsc-monitoring-ng; do
  status=$(aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$ng" --query 'nodegroup.status' --output text 2>/dev/null || echo "NOTFOUND")
  if [[ "$status" != "NOTFOUND" && "$status" != "None" ]]; then
    log "delete nodegroup $ng (status=$status)"
    aws eks delete-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$ng" >/dev/null 2>&1 || true
  fi
done

for ng in wsc-app-ng wsc-addon-ng wsc-monitoring-ng; do
  if aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$ng" >/dev/null 2>&1; then
    log "waiting delete $ng..."
    aws eks wait nodegroup-deleted --cluster-name "$CLUSTER" --nodegroup-name "$ng" 2>/dev/null || true
  fi
done

log "=== 2. EKS 고아 Auto Scaling Group ==="
for asg in $(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'eks-${PREFIX}') || contains(AutoScalingGroupName, '${PREFIX}')].AutoScalingGroupName" --output text); do
  log "delete ASG $asg"
  aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$asg" --min-size 0 --max-size 0 --desired-capacity 0 2>/dev/null || true
  aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$asg" --force-delete 2>/dev/null || true
done

log "=== 3. 고아 EC2 (EKS 실패 인스턴스) ==="
for id in $(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=wsc" "Name=instance-state-name,Values=running,stopped,pending,stopping" \
  --query 'Reservations[].Instances[?Tags[?Key==`Name` && Value!=`wsc-bastion`]].InstanceId' --output text); do
  [[ -z "$id" || "$id" == "None" ]] && continue
  log "terminate instance $id"
  aws ec2 terminate-instances --instance-ids "$id" >/dev/null 2>&1 || true
done

log "=== 4. 미연결 EIP ==="
for alloc in $(aws ec2 describe-addresses --filters "Name=tag:Project,Values=wsc" \
  --query 'Addresses[?AssociationId==null].AllocationId' --output text); do
  [[ -z "$alloc" || "$alloc" == "None" ]] && continue
  log "release EIP $alloc"
  aws ec2 release-address --allocation-id "$alloc" 2>/dev/null || true
done

log "=== 5. available ENI (Lambda/EKS 잔여) ==="
for eni in $(aws ec2 describe-network-interfaces \
  --filters "Name=tag:Project,Values=wsc" "Name=status,Values=available" \
  --query 'NetworkInterfaces[].NetworkInterfaceId' --output text); do
  [[ -z "$eni" || "$eni" == "None" ]] && continue
  log "delete ENI $eni"
  aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null || true
done

log "=== 6. 구버전 Launch Template (wsc-*) ==="
for lt in $(aws ec2 describe-launch-templates --query "LaunchTemplates[?contains(LaunchTemplateName, '${PREFIX}')].LaunchTemplateId" --output text); do
  # state에 있는 최신 LT는 terraform이 관리 — 고아만: 버전 2개 이상이면 구버전 삭제
  versions=$(aws ec2 describe-launch-template-versions --launch-template-id "$lt" --query 'LaunchTemplateVersions[].VersionNumber' --output text)
  count=$(echo "$versions" | wc -w)
  if [[ "$count" -gt 1 ]]; then
    for v in $(echo "$versions" | tr '\t' ' '); do
      latest=$(echo "$versions" | tr '\t' '\n' | sort -n | tail -1)
      if [[ "$v" != "$latest" ]]; then
        log "delete LT $lt version $v"
        aws ec2 delete-launch-template-versions --launch-template-id "$lt" --versions "$v" 2>/dev/null || true
      fi
    done
  fi
done

log "=== 7. Terraform deposed 정리 ==="
"$ROOT/terraform" -chdir="$DIR" apply -input=false -auto-approve -refresh-only 2>/dev/null || true
"$ROOT/terraform" -chdir="$DIR" apply -input=false -auto-approve \
  -target=aws_launch_template.node \
  2>/dev/null || log "(terraform apply deposed — 수동 확인 필요)"

log "=== 완료 ==="
aws ec2 describe-instances --filters "Name=tag:Project,Values=wsc" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,State:State.Name}' --output table 2>/dev/null || true
