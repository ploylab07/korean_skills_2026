#!/usr/bin/env bash
# Wipe day3 leftovers (Linux). Requires aws CLI + valid credentials.
# Naming from .env: DAY3_PROJECT + DAY3_ENVIRONMENT, or APDEV_PREFIX, or defaults apdev-dev.
set -euo pipefail
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
if [[ -n "${APDEV_PREFIX:-}" ]]; then
  PREFIX="$APDEV_PREFIX"
else
  PREFIX="${DAY3_PROJECT:-apdev}-${DAY3_ENVIRONMENT:-dev}"
fi
DB_ID="${DB_IDENTIFIER:-${TF_VAR_db_identifier:-apdev-rds-instance}}"
export AWS_DEFAULT_REGION="$REGION"

quiet() { aws "$@" >/dev/null 2>&1 || true; }
txt() { aws "$@" 2>/dev/null | tr '\t' '\n' | sed '/^$/d;/^None$/d;/^null$/d' || true; }

echo ">>> Wiping day3 leftovers named ${PREFIX}-* (region=$REGION)"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
if [[ -z "$ACCOUNT" ]]; then
  echo "[!] AWS credentials invalid - abort wipe" >&2
  exit 1
fi

CLUSTER="${PREFIX}-cluster"
if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  for ng in $(txt eks list-nodegroups --cluster-name "$CLUSTER" --query 'nodegroups[]' --output text); do
    echo "  delete nodegroup $ng"
    quiet eks delete-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$ng"
    quiet eks wait nodegroup-deleted --cluster-name "$CLUSTER" --nodegroup-name "$ng"
  done
  echo "  delete EKS $CLUSTER"
  quiet eks delete-cluster --name "$CLUSTER"
  quiet eks wait cluster-deleted --name "$CLUSTER"
fi

if aws rds describe-db-instances --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
  echo "  delete RDS $DB_ID"
  quiet rds delete-db-instance --db-instance-identifier "$DB_ID" --skip-final-snapshot --delete-automated-backups
  quiet rds wait db-instance-deleted --db-instance-identifier "$DB_ID"
fi
quiet rds delete-db-subnet-group --db-subnet-group-name "${PREFIX}-db-subnet"
quiet rds delete-db-parameter-group --db-parameter-group-name "${PREFIX}-mysql8"

for repo in "${PREFIX}-user" "${PREFIX}-product" "${PREFIX}-stress"; do
  echo "  delete ECR $repo"
  quiet ecr delete-repository --repository-name "$repo" --force
done

for bucket in "${PREFIX}-images-${ACCOUNT}" "${PREFIX}-alb-logs-${ACCOUNT}"; do
  if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    echo "  delete S3 $bucket"
    quiet s3 rm "s3://$bucket" --recursive
    quiet s3api delete-bucket --bucket "$bucket"
  fi
done

# Exact names + any role whose name starts with PREFIX- (module name_prefix leftovers)
mapfile -t ROLES < <(
  {
    printf '%s\n' \
      "${PREFIX}-rds-monitoring" \
      "${PREFIX}-product-pod" \
      "${PREFIX}-db-init-pod" \
      "${PREFIX}-aws-lbc" \
      "${PREFIX}-cluster-autoscaler" \
      "${PREFIX}-cluster" \
      "${PREFIX}-main-eks-node-group"
    txt iam list-roles --query "Roles[?starts_with(RoleName, \`${PREFIX}\`)].RoleName" --output text
  } | awk 'NF' | sort -u
)
for role in "${ROLES[@]}"; do
  echo "  delete IAM role $role"
  for ip in $(txt iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[].InstanceProfileName' --output text); do
    quiet iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$role"
    quiet iam delete-instance-profile --instance-profile-name "$ip"
  done
  for pol in $(txt iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text); do
    quiet iam detach-role-policy --role-name "$role" --policy-arn "$pol"
  done
  for pol in $(txt iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text); do
    quiet iam delete-role-policy --role-name "$role" --policy-name "$pol"
  done
  quiet iam delete-role --role-name "$role"
done

for parn in $(txt iam list-policies --scope Local --query "Policies[?starts_with(PolicyName, \`${PREFIX}\`)].Arn" --output text); do
  echo "  delete IAM policy $parn"
  for ver in $(txt iam list-policy-versions --policy-arn "$parn" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text); do
    quiet iam delete-policy-version --policy-arn "$parn" --version-id "$ver"
  done
  quiet iam delete-policy --policy-arn "$parn"
done

for wid in $(txt wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?Name=='${PREFIX}-waf'].Id" --output text); do
  lock="$(txt wafv2 get-web-acl --scope REGIONAL --id "$wid" --name "${PREFIX}-waf" --query LockToken --output text)"
  echo "  delete WAF ${PREFIX}-waf"
  quiet wafv2 delete-web-acl --scope REGIONAL --id "$wid" --name "${PREFIX}-waf" --lock-token "$lock"
done

for lg in "aws-waf-logs-${PREFIX}" "/aws/eks/${PREFIX}-cluster/cluster"; do
  echo "  delete log group $lg"
  quiet logs delete-log-group --log-group-name "$lg"
done

quiet kms delete-alias --alias-name "alias/eks/${PREFIX}-cluster"

for topic in $(txt sns list-topics --query "Topics[?contains(TopicArn, '${PREFIX}-alerts')].TopicArn" --output text); do
  echo "  delete SNS $topic"
  quiet sns delete-topic --topic-arn "$topic"
done

for a in $(txt cloudwatch describe-alarms --alarm-name-prefix "$PREFIX" --query 'MetricAlarms[].AlarmName' --output text); do
  quiet cloudwatch delete-alarms --alarm-names "$a"
done

for p in $(txt codebuild list-projects --output text); do
  case "$p" in
    ${PREFIX}-*-img|${PREFIX}-day3*) echo "  delete CodeBuild $p"; quiet codebuild delete-project --name "$p" ;;
  esac
done

VPC="$(txt ec2 describe-vpcs --filters Name=tag:Name,Values="$PREFIX" --query 'Vpcs[0].VpcId' --output text)"
if [[ -z "$VPC" || "$VPC" == "None" ]]; then
  VPC="$(txt ec2 describe-vpcs --filters Name=tag:Project,Values=apdev Name=tag:Environment,Values=dev --query 'Vpcs[0].VpcId' --output text)"
fi
if [[ -n "$VPC" && "$VPC" != "None" ]]; then
  echo "  cleanup VPC $VPC"
  for nat in $(txt ec2 describe-nat-gateways --filter Name=vpc-id,Values="$VPC" Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text); do
    quiet ec2 delete-nat-gateway --nat-gateway-id "$nat"
  done
  for i in $(seq 1 40); do
    left="$(txt ec2 describe-nat-gateways --filter Name=vpc-id,Values="$VPC" Name=state,Values=available,pending,deleting --query 'NatGateways[].NatGatewayId' --output text)"
    [[ -z "$left" ]] && break
    sleep 10
  done
  for ep in $(txt ec2 describe-vpc-endpoints --filters Name=vpc-id,Values="$VPC" --query 'VpcEndpoints[].VpcEndpointId' --output text); do
    quiet ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ep"
  done
  for igw in $(txt ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC" --query 'InternetGateways[].InternetGatewayId' --output text); do
    quiet ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC"
    quiet ec2 delete-internet-gateway --internet-gateway-id "$igw"
  done
  for rt in $(txt ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text); do
    quiet ec2 delete-route-table --route-table-id "$rt"
  done
  for sn in $(txt ec2 describe-subnets --filters Name=vpc-id,Values="$VPC" --query 'Subnets[].SubnetId' --output text); do
    quiet ec2 delete-subnet --subnet-id "$sn"
  done
  for i in $(seq 1 8); do
    sgs="$(txt ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)"
    [[ -z "$sgs" ]] && break
    for sg in $sgs; do quiet ec2 delete-security-group --group-id "$sg"; done
    sleep 5
  done
  quiet ec2 delete-vpc --vpc-id "$VPC"
fi

echo "[OK] day3 leftover wipe finished"
