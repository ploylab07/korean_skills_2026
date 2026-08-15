#!/usr/bin/env bash
# File-based scoring simulation against day1/007 1과제_채점지.pdf (total 30 = 100%)
# No live AWS required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCORE=0
MISS=0
ok()  { local pts="$1"; shift; echo "[PASS +${pts}] $*"; SCORE="$(awk -v a="$SCORE" -v b="$pts" 'BEGIN{printf "%.1f", a+b}')"; }
bad() { local pts="$1"; shift; echo "[FAIL -${pts}] $*"; MISS="$(awk -v a="$MISS" -v b="$pts" 'BEGIN{printf "%.1f", a+b}')"; }
has() { grep -qE "$2" "$1" 2>/dev/null; }

echo "=== day1/007 score simulation (채점기준 30점 = 100%) ==="
echo "root: $ROOT"
echo

# ----- 1 Networking (3.0) -----
if has "$ROOT/network.tf" 'Name = "unicorn-vpc"' \
  && has "$ROOT/providers.tf" '10\.97\.0\.0/16' \
  && has "$ROOT/network.tf" 'unicorn-subnet-pub-' \
  && has "$ROOT/network.tf" 'unicorn-subnet-priv-' \
  && has "$ROOT/network.tf" '10\.97\.\$\{each\.value\}\.0/24' \
  && has "$ROOT/providers.tf" 'az_suffixes[[:space:]]*=[[:space:]]*\["a", "b", "c"\]'; then
  ok 1.0 "1-1 VPC & Subnet CIDR"
else
  bad 1.0 "1-1 VPC & Subnet CIDR"
fi

if has "$ROOT/network.tf" 'Name = "unicorn-igw"' \
  && has "$ROOT/network.tf" 'Name = "unicorn-nat-' \
  && has "$ROOT/network.tf" 'Name = "unicorn-rt-pub"' \
  && has "$ROOT/network.tf" 'Name = "unicorn-rt-priv-' \
  && has "$ROOT/network.tf" 'gateway_id[[:space:]]*=[[:space:]]*aws_internet_gateway.main.id' \
  && has "$ROOT/network.tf" 'nat_gateway_id[[:space:]]*=[[:space:]]*aws_nat_gateway.main'; then
  ok 1.0 "1-2 Routing Configuration"
else
  bad 1.0 "1-2 Routing Configuration"
fi

if has "$ROOT/network.tf" '\.s3"' \
  && has "$ROOT/network.tf" 'ecr\.api' \
  && has "$ROOT/network.tf" 'ecr\.dkr' \
  && has "$ROOT/network.tf" 'resource "aws_flow_log"'; then
  ok 1.0 "1-3 VPC Endpoint & Flow Log"
else
  bad 1.0 "1-3 VPC Endpoint & Flow Log"
fi

# ----- 2 KMS (1.0) -----
if has "$ROOT/kms.tf" 'alias/unicorn-kms-app' \
  && has "$ROOT/kms.tf" 'alias/unicorn-kms-data' \
  && has "$ROOT/kms.tf" 'alias/unicorn-kms-platform' \
  && has "$ROOT/kms.tf" 'rotation_period_in_days = 90' \
  && has "$ROOT/kms.tf" 'enable_key_rotation[[:space:]]*=[[:space:]]*true' \
  && has "$ROOT/kms.tf" 'multi_region[[:space:]]*=[[:space:]]*true'; then
  ok 1.0 "2-1 Keys & Rotation"
else
  bad 1.0 "2-1 Keys & Rotation"
fi

# ----- 3 S3 (1.0) -----
if has "$ROOT/providers.tf" 'unicorn-web-\$\{local\.account_id\}' \
  && has "$ROOT/s3_ecr.tf" 'block_public_acls[[:space:]]*=[[:space:]]*true' \
  && has "$ROOT/s3_ecr.tf" 'block_public_policy[[:space:]]*=[[:space:]]*true' \
  && has "$ROOT/s3_ecr.tf" 'ignore_public_acls[[:space:]]*=[[:space:]]*true' \
  && has "$ROOT/s3_ecr.tf" 'restrict_public_buckets[[:space:]]*=[[:space:]]*true' \
  && has "$ROOT/s3_ecr.tf" 'status = "Enabled"' \
  && has "$ROOT/s3_ecr.tf" 'sse_algorithm[[:space:]]*=[[:space:]]*"aws:kms"' \
  && has "$ROOT/s3_ecr.tf" 'aws_kms_key.data'; then
  ok 1.0 "3-1 S3 bucket Configuration"
else
  bad 1.0 "3-1 S3 bucket Configuration"
fi

# ----- 4 DynamoDB (1.5) -----
if has "$ROOT/dynamodb.tf" 'unicorn-concert-db' \
  && has "$ROOT/dynamodb.tf" 'PAY_PER_REQUEST' \
  && has "$ROOT/dynamodb.tf" 'hash_key[[:space:]]*=[[:space:]]*"booking_id"' \
  && has "$ROOT/dynamodb.tf" 'client-id-created-at-index' \
  && has "$ROOT/dynamodb.tf" 'hash_key[[:space:]]*=[[:space:]]*"client_id"' \
  && has "$ROOT/dynamodb.tf" 'range_key[[:space:]]*=[[:space:]]*"created_at"' \
  && has "$ROOT/dynamodb.tf" 'projection_type = "ALL"' \
  && has "$ROOT/dynamodb.tf" 'aws_kms_key.app' \
  && has "$ROOT/dynamodb.tf" 'point_in_time_recovery' \
  && has "$ROOT/dynamodb.tf" 'deletion_protection_enabled = true'; then
  ok 1.5 "4-1 DynamoDB Table Configuration"
else
  bad 1.5 "4-1 DynamoDB Table Configuration"
fi

# ----- 5 ECR (1.0) -----
if has "$ROOT/s3_ecr.tf" 'unicorn-concert-app' \
  && has "$ROOT/s3_ecr.tf" 'scan_on_push = true' \
  && has "$ROOT/s3_ecr.tf" 'IMMUTABLE_WITH_EXCLUSION' \
  && has "$ROOT/s3_ecr.tf" 'encryption_type = "KMS"' \
  && has "$ROOT/s3_ecr.tf" 'aws_kms_key.data' \
  && has "$ROOT/scripts/deploy-image.sh" 'v1\.0\.0' \
  && has "$ROOT/scripts/deploy-image.sh" 'latest'; then
  ok 1.0 "5-1 ECR Repository Configuration"
else
  bad 1.0 "5-1 ECR Repository Configuration"
fi

# ----- 6 EKS (4.5) -----
if has "$ROOT/providers.tf" 'cluster_name = "unicorn-eks-cluster"' \
  && has "$ROOT/eks.tf" 'version[[:space:]]*=[[:space:]]*"1\.35"' \
  && has "$ROOT/eks.tf" 'endpoint_private_access = true' \
  && has "$ROOT/eks.tf" 'endpointPublicAccess=false' \
  && has "$ROOT/eks.tf" '"api"' && has "$ROOT/eks.tf" '"audit"' && has "$ROOT/eks.tf" '"authenticator"' \
  && has "$ROOT/eks.tf" '"controllerManager"' && has "$ROOT/eks.tf" '"scheduler"' \
  && has "$ROOT/eks.tf" 'aws_kms_replica_key.platform' \
  && has "$ROOT/eks.tf" 'authentication_mode[[:space:]]*=[[:space:]]*"API"'; then
  ok 1.5 "6-1 EKS Cluster Configuration"
else
  bad 1.5 "6-1 EKS Cluster Configuration"
fi

if has "$ROOT/eks.tf" 'unicorn-k8snode-app-node' \
  && has "$ROOT/eks.tf" 'unicorn-k8snode-addon-node' \
  && has "$ROOT/eks.tf" 'unicorn = "app"' \
  && has "$ROOT/eks.tf" 'unicorn = "addon"' \
  && grep -A20 'resource "aws_eks_node_group" "app"' "$ROOT/eks.tf" | grep -q 'aws_subnet.private' \
  && grep -A20 'resource "aws_eks_node_group" "app"' "$ROOT/eks.tf" | grep -qE 'desired_size[[:space:]]*=[[:space:]]*[23]' \
  && grep -A20 'resource "aws_eks_node_group" "addon"' "$ROOT/eks.tf" | grep -qE 'desired_size[[:space:]]*=[[:space:]]*[1-9]' \
  && has "$ROOT/eks.tf" 'Asia/Seoul'; then
  ok 1.5 "6-2 EKS NodeGroup Configuration"
else
  bad 1.5 "6-2 EKS NodeGroup Configuration"
fi

if has "$ROOT/k8s.tf" 'unicorn-book-app-deploy' \
  && has "$ROOT/k8s.tf" 'unicorn-book-app-svc' \
  && has "$ROOT/k8s.tf" 'name[[:space:]]*=[[:space:]]*"book"' \
  && has "$ROOT/k8s.tf" 'path = "/health"' \
  && has "$ROOT/k8s.tf" 'termination_grace_period_seconds = 45' \
  && has "$ROOT/k8s.tf" 'sleep 15' \
  && has "$ROOT/k8s.tf" 'unicorn = "app"' \
  && has "$ROOT/k8s.tf" 'unicorn-book-app-sa' \
  && has "$ROOT/eks.tf" 'unicorn-book-app-sa' \
  && has "$ROOT/k8s.tf" 'replicas = 2' \
  && has "$ROOT/Dockerfile" 'alpine'; then
  ok 1.5 "6-3 Workload Check"
else
  bad 1.5 "6-3 Workload Check"
fi

# ----- 7 Lambda (1.0) -----
if has "$ROOT/lambda.tf" 'unicorn-get-booking-func' \
  && has "$ROOT/lambda.tf" '/unicorn/lambda/get-booking' \
  && has "$ROOT/lambda.tf" 'aws_kms_replica_key.platform' \
  && has "$ROOT/lambda/lambda_function.py" 'booking_id' \
  && has "$ROOT/lambda/lambda_function.py" 'TABLE_NAME'; then
  ok 1.0 "7-1 Lambda Function Configuration"
else
  bad 1.0 "7-1 Lambda Function Configuration"
fi

# ----- 8 Service Endpoint (7.0) -----
if has "$ROOT/alb.tf" 'name[[:space:]]*=[[:space:]]*"unicorn-alb"' \
  && has "$ROOT/alb.tf" 'internal[[:space:]]*=[[:space:]]*true' \
  && has "$ROOT/alb.tf" 'name[[:space:]]*=[[:space:]]*"unicorn-tg"' \
  && has "$ROOT/alb.tf" 'port[[:space:]]*=[[:space:]]*80' \
  && has "$ROOT/alb.tf" 'protocol[[:space:]]*=[[:space:]]*"HTTP"' \
  && has "$ROOT/alb.tf" '"POST"' && has "$ROOT/alb.tf" '"GET"' \
  && has "$ROOT/alb.tf" '/health' \
  && has "$ROOT/alb.tf" 'aws_lb_target_group.lambda'; then
  ok 1.0 "8-1 ALB Routing Configuration"
else
  bad 1.0 "8-1 ALB Routing Configuration"
fi

if has "$ROOT/cloudfront.tf" 'comment[[:space:]]*=[[:space:]]*"unicorn-svc-cf"' \
  && has "$ROOT/cloudfront.tf" 's3-origin' \
  && has "$ROOT/cloudfront.tf" 'app-origin' \
  && has "$ROOT/cloudfront.tf" 'aws_cloudfront_vpc_origin' \
  && has "$ROOT/cloudfront.tf" 'origin_access_control' \
  && has "$ROOT/cloudfront.tf" 'cloudfront.amazonaws.com' \
  && has "$ROOT/cloudfront.tf" 'AWS:SourceArn'; then
  ok 1.5 "8-2 CloudFront CDN Configuration"
else
  bad 1.5 "8-2 CloudFront CDN Configuration"
fi

# POST/GET = 1.5 each (Service Endpoint major 7.0 = 1+1.5+1.5+1.5+0.5+1)
if has "$ROOT/cloudfront.tf" '/v1/book' \
  && has "$ROOT/alb.tf" '/v1/book' \
  && has "$ROOT/k8s.tf" 'TABLE_NAME' \
  && has "$ROOT/k8s.tf" ':v1\.0\.0'; then
  ok 1.5 "8-3 Book app POST Request"
else
  bad 1.5 "8-3 Book app POST Request"
fi

if has "$ROOT/alb.tf" 'aws_lb_target_group.lambda' \
  && grep -A35 'resource "aws_lb_listener_rule" "book_get"' "$ROOT/alb.tf" | grep -q '"GET"' \
  && has "$ROOT/lambda/lambda_function.py" 'get_item'; then
  ok 1.5 "8-4 Book app GET Request"
else
  bad 1.5 "8-4 Book app GET Request"
fi

if has "$ROOT/alb.tf" 'internal[[:space:]]*=[[:space:]]*true' \
  && has "$ROOT/alb.tf" 'status_code[[:space:]]*=[[:space:]]*"403"' \
  && has "$ROOT/alb.tf" 'origin_verify'; then
  ok 0.5 "8-5 ALB Direct Request deny"
else
  bad 0.5 "8-5 ALB Direct Request deny"
fi

if has "$ROOT/cloudfront.tf" 'unicorn-waf' \
  && has "$ROOT/cloudfront.tf" 'AWSManagedRulesCommonRuleSet' \
  && has "$ROOT/cloudfront.tf" 'AWSManagedRulesKnownBadInputsRuleSet' \
  && has "$ROOT/cloudfront.tf" 'override_action' \
  && has "$ROOT/cloudfront.tf" 'none \{\}'; then
  ok 1.0 "8-6 WAF Managed Rule Test"
else
  bad 1.0 "8-6 WAF Managed Rule Test"
fi

# ----- 9 Security (2.0) -----
if has "$ROOT/iam.tf" 'unicorn-audit-role' \
  && has "$ROOT/iam.tf" 'max_session_duration = 3600' \
  && has "$ROOT/iam.tf" 'unicorn-audit-2026' \
  && has "$ROOT/iam.tf" 'sts:ExternalId' \
  && has "$ROOT/iam.tf" 'dynamodb:GetItem' \
  && has "$ROOT/iam.tf" 'ec2:DescribeVpcs' \
  && has "$ROOT/iam.tf" 'eks:DescribeCluster' \
  && ! grep -qE 'Action[[:space:]]*=[[:space:]]*"\*"' "$ROOT/iam.tf"; then
  ok 0.5 "9-1 Audit Role Configuration"
else
  bad 0.5 "9-1 Audit Role Configuration"
fi

if has "$ROOT/iam.tf" 'sts:ExternalId' \
  && has "$ROOT/iam.tf" 'unicorn-audit-2026\$\{local\.bib\}' \
  && has "$ROOT/providers.tf" 'bib[[:space:]]*=[[:space:]]*"007"'; then
  ok 1.5 "9-2 Audit Role Assume and Permission"
else
  bad 1.5 "9-2 Audit Role Assume and Permission"
fi

# ----- 10 Application (1.5) -----
if has "$ROOT/k8s.tf" 'AWS_REGION' \
  && has "$ROOT/k8s.tf" 'TABLE_NAME' \
  && has "$ROOT/k8s.tf" 'aws_dynamodb_table.concert.name' \
  && has "$ROOT/alb.tf" '/health' \
  && has "$ROOT/cloudfront.tf" '/health'; then
  ok 1.5 "10-1 Application Health and env"
else
  bad 1.5 "10-1 Application Health and env"
fi

# ----- 11 Observability (2.0) -----
if has "$ROOT/observability.tf" '/unicorn/eks/book-app' \
  && has "$ROOT/observability.tf" 'Exclude' \
  && has "$ROOT/observability.tf" 'path=/health' \
  && has "$ROOT/observability.tf" 'client_ip' \
  && has "$ROOT/observability.tf" 'status_code' \
  && has "$ROOT/observability.tf" 'timestamp'; then
  ok 1.5 "11-1 Log type & Health log exclusion"
else
  bad 1.5 "11-1 Log type & Health log exclusion"
fi

if has "$ROOT/observability.tf" 'kubeControllerManager.enabled' \
  && has "$ROOT/observability.tf" 'kubeScheduler.enabled' \
  && has "$ROOT/observability.tf" 'kubeEtcd.enabled' \
  && grep -A0 'kubeControllerManager.enabled' "$ROOT/observability.tf" | grep -q 'false' \
  && has "$ROOT/observability.tf" 'kube-prometheus-stack'; then
  ok 0.5 "11-2 Prometheus Metrics"
else
  bad 0.5 "11-2 Prometheus Metrics"
fi

# ----- 12 Runtime Test (3.0) -----
if has "$ROOT/observability.tf" 'Flush[[:space:]]+1' \
  && has "$ROOT/observability.tf" 'cloudwatch_logs' \
  && has "$ROOT/observability.tf" 'aws-for-fluent-bit' \
  && has "$ROOT/observability.tf" 'normalize\.lua'; then
  ok 1.5 "12-1 Log Pipeline Test"
else
  bad 1.5 "12-1 Log Pipeline Test"
fi

if has "$ROOT/cloudfront.tf" 'unicorn-rate-limit' \
  && has "$ROOT/cloudfront.tf" 'limit[[:space:]]*=[[:space:]]*50' \
  && has "$ROOT/cloudfront.tf" 'evaluation_window_sec[[:space:]]*=[[:space:]]*60' \
  && has "$ROOT/cloudfront.tf" 'Request blocked by Unicorn WAF' \
  && has "$ROOT/cloudfront.tf" 'response_code[[:space:]]*=[[:space:]]*403' \
  && has "$ROOT/cloudfront.tf" 'aws-waf-logs-unicorn'; then
  ok 1.5 "12-2 WAF Rate limit block Test"
else
  bad 1.5 "12-2 WAF Rate limit block Test"
fi

# ----- 13 Grafana (1.5) -----
DASH="$ROOT/k8s/dashboards/unicorn-grafana-dashboard.json"
if has "$DASH" 'EKS Node CPU Usage' \
  && has "$DASH" 'EKS Node Memory Usage' \
  && has "$DASH" 'unicorn Namespace Pod Status' \
  && has "$DASH" 'Book App Ready' \
  && has "$DASH" 'Book App HTTP Request Duration' \
  && has "$DASH" '"type": "timeseries"' \
  && has "$DASH" '"type": "stat"' \
  && has "$DASH" 'graphMode' \
  && has "$ROOT/observability.tf" 'unicorn-grafana-dashboard' \
  && has "$ROOT/alb.tf" 'unicorn-grafana-alb' \
  && has "$ROOT/alb.tf" 'unicorn-grafana-tg' \
  && has "$ROOT/providers.tf" 'skills\$\{local\.bib\}' \
  && has "$ROOT/providers.tf" 'HelloKrSkills!'; then
  ok 1.5 "13-1 Grafana Dashboard Panel Configuration"
else
  bad 1.5 "13-1 Grafana Dashboard Panel Configuration"
fi

PCT="$(awk -v s="$SCORE" 'BEGIN{printf "%.1f", (s/30.0)*100}')"
echo
echo "=== SCORE: ${SCORE} / 30.0  (${PCT}%)  missed=${MISS} ==="
awk -v s="$SCORE" 'BEGIN{exit !(s+0 >= 30.0)}'
