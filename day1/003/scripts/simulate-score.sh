#!/usr/bin/env bash
# Static simulation against mark.sh + 채점기준 (no live AWS apply required)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCORE=0
MISS=0
ok()  { local pts=$1; shift; echo "[PASS] (+${pts}) $*"; SCORE="$(awk -v a="$SCORE" -v b="$pts" 'BEGIN{printf "%.1f", a+b}')"; }
bad() { local pts=$1; shift; echo "[FAIL] (-${pts}) $*"; MISS="$(awk -v a="$MISS" -v b="$pts" 'BEGIN{printf "%.1f", a+b}')"; }
has() { grep -qE "$2" "$1" 2>/dev/null; }
hasf() { [[ -f "$1" ]] && grep -qE "$2" "$1" 2>/dev/null; }

echo "=== day1/003 score simulation (file-based) ==="
echo "root: $ROOT"
echo

# ----- 1 Networking 2.0 -----
if has "$ROOT/network.tf" 'cidr_block\s*=\s*"192.168.0.0/16"' \
  && has "$ROOT/network.tf" 'wsc2026-skills-vpc' \
  && has "$ROOT/network.tf" 'wsc2026-skills-hub-sub-a' && has "$ROOT/network.tf" '192.168.1.0/24' \
  && has "$ROOT/network.tf" 'wsc2026-skills-hub-sub-b' && has "$ROOT/network.tf" '192.168.10.0/24' \
  && has "$ROOT/network.tf" 'wsc2026-skills-app-sub-a' && has "$ROOT/network.tf" '192.168.2.0/24' \
  && has "$ROOT/network.tf" 'wsc2026-skills-app-sub-b' && has "$ROOT/network.tf" '192.168.20.0/24'; then
  ok 1.0 "1-1 VPC/Subnets"
else
  bad 1.0 "1-1 VPC/Subnets"
fi

if has "$ROOT/network.tf" 'wsc2026-skills-igw' \
  && has "$ROOT/network.tf" 'wsc2026-skills-nat-a' && has "$ROOT/network.tf" 'wsc2026-skills-nat-b' \
  && has "$ROOT/network.tf" 'wsc2026-skills-hub-rtb' \
  && has "$ROOT/network.tf" 'wsc2026-skills-app-rtb-a' && has "$ROOT/network.tf" 'wsc2026-skills-app-rtb-b' \
  && has "$ROOT/network.tf" 'gateway_id = aws_internet_gateway.main.id' \
  && has "$ROOT/network.tf" 'nat_gateway_id = aws_nat_gateway.nat_a.id' \
  && has "$ROOT/network.tf" 'nat_gateway_id = aws_nat_gateway.nat_b.id' \
  && has "$ROOT/network.tf" 'mark-sg'; then
  ok 1.0 "1-2 Routing + mark-sg"
else
  bad 1.0 "1-2 Routing + mark-sg"
fi

# ----- 2 Database 1.3 -----
if has "$ROOT/dynamodb.tf" 'wsc2026-book-table' \
  && has "$ROOT/dynamodb.tf" 'hash_key\s*=\s*"client_id"' \
  && has "$ROOT/dynamodb.tf" 'PAY_PER_REQUEST' \
  && has "$ROOT/dynamodb.tf" 'deletion_protection_enabled\s*=\s*true' \
  && has "$ROOT/dynamodb.tf" 'booking_id-index' \
  && has "$ROOT/dynamodb.tf" 'recovery_period_in_days\s*=\s*35' \
  && has "$ROOT/dynamodb.tf" 'dynamodb:PutItem' && has "$ROOT/dynamodb.tf" 'dynamodb:Query' \
  && has "$ROOT/kms.tf" 'alias/wsc2026-db-kms' \
  && ! grep -vE '^\s*#' "$ROOT/kms.tf" | grep -q '"kms:\*"' \
  && ! grep -vE '^\s*#' "$ROOT/kms.tf" | grep -qE '":root"|AWS.*:root'; then
  ok 1.3 "2-1 DynamoDB + KMS"
else
  bad 1.3 "2-1 DynamoDB + KMS"
fi

# ----- 3 ECR 1.2 -----
if has "$ROOT/ecr.tf" 'wsc2026-book-ecr' \
  && has "$ROOT/ecr.tf" 'scan_on_push\s*=\s*true' \
  && has "$ROOT/ecr.tf" 'MUTABLE_WITH_EXCLUSION' \
  && has "$ROOT/ecr.tf" 'v1\*' \
  && has "$ROOT/ecr.tf" 'encryption_type\s*=\s*"KMS"' \
  && has "$ROOT/kms.tf" 'alias/wsc2026-ecr-kms' \
  && has "$ROOT/scripts/deploy.sh" 'IMAGE_TAG="v1.0.0"'; then
  ok 1.2 "3-1 ECR"
else
  bad 1.2 "3-1 ECR"
fi

# ----- 4 Orchestration 3.0 -----
if has "$ROOT/eks.tf" 'version\s*=\s*"1.35"' \
  && has "$ROOT/eks.tf" 'endpoint_public_access\s*=\s*false' \
  && has "$ROOT/eks.tf" 'endpoint_private_access\s*=\s*true' \
  && has "$ROOT/eks.tf" 'enabled_cluster_log_types' \
  && has "$ROOT/eks.tf" 'wsc2026.skills.local' \
  && has "$ROOT/kms.tf" 'alias/wsc2026-eks-kms' \
  && has "$ROOT/eks.tf" 'aws_kms_key.eks'; then
  ok 1.5 "4-1 EKS Cluster"
else
  bad 1.5 "4-1 EKS Cluster"
fi

if has "$ROOT/eks.tf" 'wsc2026-addon-nodegroup' && has "$ROOT/eks.tf" 'wsc2026-workload-ng' \
  && has "$ROOT/eks.tf" 't3.medium' \
  && has "$ROOT/eks.tf" '"wsc2026/node" = "addon"' \
  && has "$ROOT/eks.tf" '"wsc2026/node" = "application"' \
  && has "$ROOT/eks.tf" 'Name = "wsc2026-addon-node"' \
  && has "$ROOT/eks.tf" 'Name = "wsc2026-workload-node"' \
  && has "$ROOT/eks.tf" 'aws_launch_template.addon' \
  && has "$ROOT/eks.tf" 'aws_launch_template.workload'; then
  ok 1.0 "4-2 NodeGroups + instance Name LT"
else
  bad 1.0 "4-2 NodeGroups + instance Name LT"
fi

if has "$ROOT/iam.tf" 'wsc2026-eks-cluster-role' \
  && has "$ROOT/iam.tf" 'wsc2026-eks-addon-node-role' \
  && has "$ROOT/iam.tf" 'wsc2026-eks-workload-node-role' \
  && ! grep -q 'AdministratorAccess' "$ROOT/iam.tf"; then
  ok 0.5 "4-3 EKS IAM (no Admin)"
else
  bad 0.5 "4-3 EKS IAM"
fi

# ----- 5 Deployment 6.5 -----
BOOK="$ROOT/k8s/book-app.yaml"
if hasf "$BOOK" 'wsc2026-book-deploy' && hasf "$BOOK" 'wsc2026-book-svc' \
  && hasf "$BOOK" 'wsc2026-book-ingress' && hasf "$BOOK" 'wsc2026-book-pdb' \
  && hasf "$BOOK" 'wsc2026-app-alb' && hasf "$BOOK" 'response-403' \
  && hasf "$BOOK" 'minAvailable: 1' && hasf "$BOOK" 'replicas: 2'; then
  ok 1.5 "5-1 Resources"
else
  bad 1.5 "5-1 Resources"
fi

if hasf "$BOOK" 'wsc2026/node: application' \
  && hasf "$BOOK" 'topology.kubernetes.io/zone' \
  && hasf "$BOOK" 'cpu: 250m' && hasf "$BOOK" 'memory: 512Mi' \
  && hasf "$BOOK" 'PreferClose'; then
  ok 1.0 "5-2 Scheduling & Resources"
else
  bad 1.0 "5-2 Scheduling & Resources"
fi

if hasf "$BOOK" 'startupProbe' && hasf "$BOOK" 'readinessProbe' && hasf "$BOOK" 'livenessProbe' \
  && hasf "$BOOK" 'path: /health' && hasf "$BOOK" 'port: 8080' \
  && hasf "$BOOK" 'name: book-config' \
  && hasf "$BOOK" 'TABLE_NAME: wsc2026-book-table' \
  && hasf "$BOOK" 'AWS_REGION: ap-northeast-2'; then
  ok 1.0 "5-3 Probes & ConfigMap"
else
  bad 1.0 "5-3 Probes & ConfigMap"
fi

if hasf "$BOOK" 'nodeSelector:' && hasf "$BOOK" 'wsc2026/node: application' \
  && has "$ROOT/network.tf" 'cluster_sg_from_alb_8080' \
  && has "$ROOT/network.tf" 'cluster_security_group_id'; then
  ok 1.5 "5-4 Placement + ALB→cluster SG"
else
  bad 1.5 "5-4 Placement + ALB→cluster SG"
fi

if has "$ROOT/eks.tf" 'wsc2026-book-sa' && has "$ROOT/iam.tf" 'wsc2026-book-pod-role' \
  && has "$ROOT/dynamodb.tf" 'wsc2026-book-pod-policy' \
  && has "$ROOT/dynamodb.tf" 'dynamodb:PutItem' \
  && has "$ROOT/eks.tf" 'eks-pod-identity-agent' \
  && ! grep -A20 'wsc2026-book-pod-policy' "$ROOT/dynamodb.tf" | grep -qE '"\*"'; then
  ok 1.5 "5-5 Pod Identity"
else
  bad 1.5 "5-5 Pod Identity"
fi

# ----- 6 S3 1.0 -----
if has "$ROOT/locals.tf" 'wsc2026-static-....-bucket|wsc2026-static-' \
  && has "$ROOT/s3.tf" 'static/index.html' && has "$ROOT/s3.tf" 'static/main.jpeg' \
  && has "$ROOT/s3.tf" 'block_public_acls\s*=\s*true' \
  && has "$ROOT/s3.tf" 'aws:kms' && has "$ROOT/s3.tf" 'bucket_key_enabled\s*=\s*true' \
  && has "$ROOT/kms.tf" 'alias/wsc2026-bucket-kms'; then
  ok 1.0 "6-1 S3"
else
  bad 1.0 "6-1 S3"
fi

# ----- 7 Lambda 3.0 -----
if has "$ROOT/lambda.tf" 'wsc2026-book-get-function' \
  && has "$ROOT/lambda.tf" 'python3.12' \
  && has "$ROOT/lambda.tf" 'kms_key_arn' \
  && has "$ROOT/lambda.tf" 'TABLE_NAME' \
  && has "$ROOT/kms.tf" 'alias/wsc2026-function-kms' \
  && has "$ROOT/lambda/handler.py" 'booking_id-index' \
  && has "$ROOT/lambda/handler.py" 'timedelta\(hours=9\)' \
  && has "$ROOT/lambda/handler.py" 'created_at'; then
  ok 1.5 "7-1 Lambda Function"
else
  bad 1.5 "7-1 Lambda Function"
fi

if has "$ROOT/iam.tf" 'wsc2026-book-function-role' \
  && has "$ROOT/dynamodb.tf" 'wsc2026-book-function-policy' \
  && has "$ROOT/dynamodb.tf" 'dynamodb:Query' \
  && ! grep -q 'AdministratorAccess' "$ROOT/iam.tf"; then
  ok 1.5 "7-2 Lambda IAM"
else
  bad 1.5 "7-2 Lambda IAM"
fi

# ----- 8 ALB 1.3 -----
if hasf "$BOOK" 'wsc2026-app-alb' \
  && hasf "$BOOK" 'internet-facing' \
  && has "$ROOT/network.tf" 'wsc2026-app-alb-sg' \
  && has "$ROOT/network.tf" 'prefix_list_ids' \
  && hasf "$BOOK" 'statusCode' && hasf "$BOOK" '403'; then
  ok 1.3 "8-1 ALB + CF-only SG + 403"
else
  bad 1.3 "8-1 ALB"
fi

# ----- 9 CloudFront 4.0 -----
if has "$ROOT/cloudfront.tf" 'Name = "wsc2026-cdn"' \
  && has "$ROOT/cloudfront.tf" 'default_root_object' \
  && has "$ROOT/cloudfront.tf" 'S3-static' && has "$ROOT/cloudfront.tf" 'ALB-booking' \
  && has "$ROOT/cloudfront.tf" 'Lambda-book-get'; then
  ok 1.2 "9-1 CF Distribution"
else
  bad 1.2 "9-1 CF Distribution"
fi

if has "$ROOT/locals.tf" '658327ea-f89d-4fab-a63d-7e88639e58f6' \
  && has "$ROOT/locals.tf" '4135ea2d-6df8-44a3-9df3-4b5a84be39ad' \
  && has "$ROOT/cloudfront.tf" 'cache_policy_optimized' \
  && has "$ROOT/cloudfront.tf" 'cache_policy_disabled'; then
  ok 1.3 "9-2 Cache Policy"
else
  bad 1.3 "9-2 Cache Policy"
fi

if has "$ROOT/cloudfront.tf" '/booking\*' \
  && has "$ROOT/cloudfront.tf" '/v1/book\*' \
  && has "$ROOT/cloudfront.tf" 'booking_rewrite' \
  && has "$ROOT/cloudfront.tf" 'uri.replace' \
  && has "$ROOT/cloudfront.tf" "/v1/book" \
  && has "$ROOT/lambda/handler.py" 'OrderedDict' \
  && has "$ROOT/lambda/handler.py" 'KST'; then
  ok 1.5 "9-3 POST/GET E2E path"
else
  bad 1.5 "9-3 POST/GET E2E path"
fi

# ----- 10 WAF 1.5 -----
if has "$ROOT/cloudfront.tf" 'wsc2026-waf' \
  && has "$ROOT/cloudfront.tf" 'AWSManagedRulesSQLiRuleSet' \
  && has "$ROOT/cloudfront.tf" 'AWSManagedRulesCommonRuleSet' \
  && has "$ROOT/cloudfront.tf" 'limit\s*=\s*200' \
  && has "$ROOT/cloudfront.tf" 'web_acl_id'; then
  ok 1.5 "10-1 WAF"
else
  bad 1.5 "10-1 WAF"
fi

# ----- 11 Observability 5.2 -----
OBS="$ROOT/k8s/observability.yaml"
if hasf "$OBS" 'namespace: observability' \
  && hasf "$OBS" 'name: prometheus' && hasf "$OBS" 'name: grafana' && hasf "$OBS" 'name: fluent-bit' \
  && hasf "$OBS" 'wsc2026/node: addon' \
  && hasf "$OBS" 'storage.tsdb.retention.time=7d' \
  && hasf "$OBS" 'node-exporter'; then
  ok 1.2 "11-1 Observability Deploy"
else
  bad 1.2 "11-1 Observability Deploy"
fi

if hasf "$OBS" 'type: prometheus' && hasf "$OBS" 'type: alertmanager' && hasf "$OBS" 'type: cloudwatch' \
  && hasf "$OBS" 'Skills\$#\$@!' \
  && hasf "$OBS" 'wsc2026-grafana-dashboard' \
  && hasf "$OBS" 'LoadBalancer'; then
  ok 1.0 "11-2 Grafana Datasource/Dashboard meta"
else
  bad 1.0 "11-2 Grafana Datasource/Dashboard meta"
fi

if hasf "$OBS" 'Node CPU' && hasf "$OBS" 'Node Memory' && hasf "$OBS" 'Available Nodes' \
  && hasf "$OBS" 'Pod CPU' && hasf "$OBS" 'Pod Memory' && hasf "$OBS" 'Pending' \
  && hasf "$OBS" 'Application Logs' \
  && hasf "$OBS" 'RequestCount' && hasf "$OBS" 'ResponseTime' && hasf "$OBS" 'StatusCodes' \
  && hasf "$OBS" 'http_requests_total' \
  && hasf "$OBS" '"value":80' \
  && hasf "$OBS" 'cloudwatch_logs' \
  && hasf "$OBS" 'Exclude_Path'; then
  ok 1.5 "11-3 Dashboard panels + FluentBit→CW"
else
  bad 1.5 "11-3 Dashboard panels + FluentBit→CW"
fi

if hasf "$OBS" 'PodHighCPU' && hasf "$OBS" 'PodHighMemory' \
  && hasf "$OBS" 'PodNotReady' && hasf "$OBS" 'HighErrorRate' && hasf "$OBS" 'HighLatency' \
  && hasf "$OBS" 'Active Alerts'; then
  ok 1.5 "11-4 Alert rules + Active Alerts panel"
else
  bad 1.5 "11-4 Alert rules + Active Alerts panel"
fi

# ----- account_id hygiene (hard requirement) -----
if has "$ROOT/locals.tf" 'account_id\s*=\s*data.aws_caller_identity.current.account_id' \
  && ! grep -qE 'default = "[0-9]{12}"' "$ROOT/variables.tf"; then
  echo "[PASS] account_id from caller identity"
else
  echo "[FAIL] account_id must use data.aws_caller_identity (not hardcoded)"
  MISS="$(awk -v a="$MISS" 'BEGIN{printf "%.1f", a+0.1}')"
fi

PCT="$(awk -v s="$SCORE" 'BEGIN{printf "%.1f", (s/30.0)*100}')"
echo
echo "=== SCORE: ${SCORE} / 30.0  (${PCT}%)  missed=${MISS} ==="
if awk -v s="$SCORE" 'BEGIN{exit !(s+0 >= 30.0)}' && awk -v m="$MISS" 'BEGIN{exit !(m+0 == 0)}'; then
  exit 0
fi
exit 1
