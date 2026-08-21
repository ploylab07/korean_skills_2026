#!/usr/bin/env bash
# File-based scoring simulation against 1과제-채점기준.pdf (total 30 = 100%)
# No live AWS required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCORE=0
MISS=0
ok()  { local pts="$1"; shift; echo "[PASS +${pts}] $*"; SCORE="$(awk -v a="$SCORE" -v b="$pts" 'BEGIN{printf "%.1f", a+b}')"; }
bad() { local pts="$1"; shift; echo "[FAIL -${pts}] $*"; MISS="$(awk -v a="$MISS" -v b="$pts" 'BEGIN{printf "%.1f", a+b}')"; }
has() { grep -qE "$2" "$1" 2>/dev/null; }

echo "=== day1/006 score simulation (채점기준 30점 = 100%) ==="
echo "root: $ROOT"
echo

# ----- 1 Network Configuration (3.0) -----
# 1-1 VPC 1.0
if has "$ROOT/network.tf" 'Name = "gj2026-vpc"' \
  && has "$ROOT/network.tf" 'cidr_block\s*=\s*"10.0.0.0/16"' \
  && has "$ROOT/network.tf" 'gj2026-private-subnet-a' && has "$ROOT/network.tf" '10.0.10.0/24' \
  && has "$ROOT/network.tf" 'gj2026-private-subnet-b' && has "$ROOT/network.tf" '10.0.11.0/24' \
  && ! has "$ROOT/network.tf" 'aws_subnet" "public'; then
  ok 1.0 "1-1 VPC (private-only CIDR)"
else
  bad 1.0 "1-1 VPC"
fi

# 1-2 Route Table 1.0 — local only (no 0.0.0.0/0 NAT)
if has "$ROOT/network.tf" 'gj2026-private-rtb-a' && has "$ROOT/network.tf" 'gj2026-private-rtb-b' \
  && ! has "$ROOT/network.tf" 'nat_gateway_id' \
  && ! has "$ROOT/network.tf" 'aws_route" ".*0.0.0.0/0'; then
  ok 1.0 "1-2 Route Tables (local only)"
else
  bad 1.0 "1-2 Route Tables"
fi

# 1-3 NAT Gateway 1.0 — zero NAT + IGW present
if ! has "$ROOT/network.tf" 'aws_nat_gateway' \
  && has "$ROOT/network.tf" 'Name = "gj2026-igw"' \
  && has "$ROOT/network.tf" 'aws_internet_gateway'; then
  ok 1.0 "1-3 NAT=0 + IGW"
else
  bad 1.0 "1-3 NAT/IGW"
fi

# ----- 2 Container Registry (2.5) -----
# 2-1 ECR 1.0
if has "$ROOT/s3_ecr.tf" 'name\s*=\s*"book"' || has "$ROOT/s3_ecr.tf" 'name                 = "book"'; then
  ok 1.0 "2-1 ECR Repository book"
else
  bad 1.0 "2-1 ECR Repository"
fi

# 2-2 Image size ≤3MB 1.5 — scratch + binary < 3MB
BIN="$ROOT/book-linux-amd64_v1.0.1"
if [[ -f "$BIN" ]] && [[ "$(wc -c < "$BIN" | tr -d ' ')" -lt 3145728 ]] \
  && has "$ROOT/Dockerfile" 'FROM scratch' \
  && has "$ROOT/Dockerfile" 'book-linux-amd64'; then
  ok 1.5 "2-2 ECR Image Size (scratch+binary<3MB)"
else
  bad 1.5 "2-2 ECR Image Size"
fi

# ----- 3 Database (2.5) -----
# 3-1 DynamoDB 1.0
if has "$ROOT/dynamodb.tf" 'name\s*=\s*"books"' \
  && (has "$ROOT/dynamodb.tf" 'hash_key\s*=\s*"booking_id"' || has "$ROOT/dynamodb.tf" 'attribute_name\s*=\s*"booking_id"') \
  && has "$ROOT/dynamodb.tf" 'client_id-index' \
  && (has "$ROOT/dynamodb.tf" 'hash_key\s*=\s*"client_id"' || has "$ROOT/dynamodb.tf" 'attribute_name\s*=\s*"client_id"'); then
  ok 1.0 "3-1 DynamoDB Configuration"
else
  bad 1.0 "3-1 DynamoDB Configuration"
fi

# 3-2 Encryption 0.5
if has "$ROOT/kms.tf" 'alias/gj2026-db-key' && has "$ROOT/dynamodb.tf" 'aws_kms_key.db'; then
  ok 0.5 "3-2 DynamoDB Encryption"
else
  bad 0.5 "3-2 DynamoDB Encryption"
fi

# 3-3 Access Restrictions 1.0 — PutItem deny for graders
if has "$ROOT/dynamodb.tf" 'dynamodb:PutItem' \
  && has "$ROOT/dynamodb.tf" 'Deny|Effect.*=.*"Deny"' \
  && (has "$ROOT/dynamodb.tf" 'ArnNotLike' || has "$ROOT/dynamodb.tf" 'StringNotEquals'); then
  ok 1.0 "3-3 DynamoDB Access Restrictions"
else
  bad 1.0 "3-3 DynamoDB Access Restrictions"
fi

# ----- 4 Container (6.5) -----
# 4-1 EKS 1.0
if has "$ROOT/eks.tf" 'gj2026-eks-cluster|local.cluster_name' \
  && has "$ROOT/providers.tf" 'cluster_name = "gj2026-eks-cluster"' \
  && has "$ROOT/eks.tf" 'version\s*=\s*"1.35"' \
  && has "$ROOT/eks.tf" 'endpoint_public_access\s*=\s*true' \
  && has "$ROOT/eks.tf" 'endpoint_private_access\s*=\s*true' \
  && has "$ROOT/kms.tf" 'alias/gj2026-eks-key' \
  && has "$ROOT/eks.tf" 'aws_kms_key.eks'; then
  ok 1.0 "4-1 EKS Configuration"
else
  bad 1.0 "4-1 EKS Configuration"
fi

# 4-2 NodeGroup 1.5
if has "$ROOT/eks.tf" 'gj2026-eks-addon-nodegroup' && has "$ROOT/eks.tf" 'gj2026-eks-app-nodegroup' \
  && has "$ROOT/eks.tf" 'BOTTLEROCKET_x86_64' \
  && has "$ROOT/eks.tf" 't3.medium' && has "$ROOT/eks.tf" 'm5.large' \
  && grep -A20 'resource "aws_eks_node_group" "addon"' "$ROOT/eks.tf" | grep -q 'desired_size = 2' \
  && grep -A20 'resource "aws_eks_node_group" "app"' "$ROOT/eks.tf" | grep -q 'desired_size = 2'; then
  ok 1.5 "4-2 NodeGroup Configuration"
else
  bad 1.5 "4-2 NodeGroup Configuration"
fi

# 4-3 Node Naming 1.5
if has "$ROOT/bootstrap/set-hostname.sh" 'gj2026\.\${IID}\.\${ROLE}\.node|gj2026\.\${IID}' \
  && has "$ROOT/eks.tf" 'hostname-override-source' \
  && has "$ROOT/eks.tf" 'hostname-bootstrap' \
  && (has "$ROOT/eks.tf" 'Name\s*=\s*"gj2026-eks-addon-node"' || has "$ROOT/eks.tf" 'Name      = "gj2026-eks-addon-node"') \
  && (has "$ROOT/eks.tf" 'Name\s*=\s*"gj2026-eks-app-node"' || has "$ROOT/eks.tf" 'Name      = "gj2026-eks-app-node"'); then
  ok 1.5 "4-3 Node Naming Convention"
else
  bad 1.5 "4-3 Node Naming Convention"
fi

# 4-4 Application Pods 1.0
if has "$ROOT/k8s/book.yaml" 'name: book' && has "$ROOT/k8s/book.yaml" 'replicas: 2' \
  && has "$ROOT/k8s/book.yaml" 'namespace: skills' \
  && has "$ROOT/k8s/book.yaml" 'name: book-svc' \
  && has "$ROOT/k8s/book.yaml" 'role: app' \
  && has "$ROOT/k8s/book.yaml" 'TABLE_NAME' && has "$ROOT/k8s/book.yaml" 'AWS_REGION'; then
  ok 1.0 "4-4 Application Pods"
else
  bad 1.0 "4-4 Application Pods"
fi

# 4-5 Network Policy 1.5 — ALB ENI /32 (not whole VPC)
if has "$ROOT/k8s/book.yaml" 'kind: NetworkPolicy' \
  && has "$ROOT/post-deploy.sh" 'ELB app/gj2026-alb' \
  && has "$ROOT/post-deploy.sh" 'cidr: \${ip}/32|/32' \
  && ! grep -A15 'kind: NetworkPolicy' "$ROOT/post-deploy.sh" | grep -q '10.0.0.0/16'; then
  ok 1.5 "4-5 Network Policy (ALB ENI only)"
else
  bad 1.5 "4-5 Network Policy"
fi

# ----- 5 Load Balancing (1.0) -----
if has "$ROOT/alb.tf" 'name\s*=\s*"gj2026-alb"' \
  && has "$ROOT/alb.tf" 'internal\s*=\s*true' \
  && has "$ROOT/alb.tf" 'gj2026-book-tg' \
  && has "$ROOT/alb.tf" 'gj2026-grafana-tg' \
  && has "$ROOT/network.tf" 'Name = "gj2026-vpc"'; then
  ok 1.0 "5-1 ALB Configuration"
else
  bad 1.0 "5-1 ALB Configuration"
fi

# ----- 6 Static Web Hosting (2.0) -----
if has "$ROOT/s3_ecr.tf" 'key\s*=\s*"index.html"' && has "$ROOT/s3_ecr.tf" 'key\s*=\s*"main.jpeg"' \
  && [[ -f "$ROOT/index.html" ]] && [[ -f "$ROOT/main.jpeg" ]] \
  && [[ "$(wc -c < "$ROOT/main.jpeg" | tr -d ' ')" == "180926" ]]; then
  ok 1.0 "6-1 S3 Object Existence"
else
  bad 1.0 "6-1 S3 Object Existence"
fi

if has "$ROOT/kms.tf" 'alias/gj2026-s3-key' && has "$ROOT/s3_ecr.tf" 'aws_kms_key.s3' \
  && has "$ROOT/s3_ecr.tf" 'sse_algorithm\s*=\s*"aws:kms"'; then
  ok 1.0 "6-2 S3 Encryption"
else
  bad 1.0 "6-2 S3 Encryption"
fi

# ----- 7 Lambda (1.0) -----
if has "$ROOT/lambda.tf" 'gj2026-book-reservation' && has "$ROOT/lambda.tf" 'python3.14' \
  && has "$ROOT/lambda/handler.py" 'client_id-index' \
  && has "$ROOT/lambda/handler.py" 'lambda_handler'; then
  ok 1.0 "7-1 Lambda Configuration"
else
  bad 1.0 "7-1 Lambda Configuration"
fi

# ----- 8 CDN (5.5) -----
# 8-1 S3 Static 1.0
if (has "$ROOT/cloudfront.tf" 'gj2026-cdn' || has "$ROOT/cloudfront.tf" 'comment\s*=\s*"gj2026-cdn"') \
  && has "$ROOT/cloudfront.tf" 'default_root_object\s*=\s*"index.html"' \
  && has "$ROOT/cloudfront.tf" 'redirect-to-https' \
  && grep -A12 'default_cache_behavior' "$ROOT/cloudfront.tf" | grep -q 's3-web\|s3'; then
  ok 1.0 "8-1 S3 Static Content"
else
  bad 1.0 "8-1 S3 Static Content"
fi

# 8-2 ALB API 1.5
if has "$ROOT/alb.tf" 'POST' && has "$ROOT/alb.tf" '/v1/book' \
  && has "$ROOT/cloudfront.tf" '/v1/\*' \
  && has "$ROOT/cloudfront.tf" 'gj2026-alb-origin|vpc_origin'; then
  ok 1.5 "8-2 ALB API (POST /v1/book)"
else
  bad 1.5 "8-2 ALB API"
fi

# 8-3 Lambda API all 1.5
if has "$ROOT/alb.tf" '/reservation' && has "$ROOT/alb.tf" 'aws_lb_target_group.lambda' \
  && has "$ROOT/lambda/handler.py" 'table.scan|scan\(' \
  && has "$ROOT/cloudfront.tf" '/reservation\*'; then
  ok 1.5 "8-3 Lambda API (GET /reservation)"
else
  bad 1.5 "8-3 Lambda API 1"
fi

# 8-4 Lambda API client_id 1.5
if has "$ROOT/lambda/handler.py" 'client_id' \
  && has "$ROOT/lambda/handler.py" 'Key\("client_id"\)|IndexName="client_id-index"'; then
  ok 1.5 "8-4 Lambda API (GET ?client_id=)"
else
  bad 1.5 "8-4 Lambda API 2"
fi

# ----- 9 WAF (3.0) -----
# 9-1 Method Restriction 1.5
if (has "$ROOT/alb.tf" 'Method Not Allowed' && has "$ROOT/alb.tf" '405') \
  || (has "$ROOT/cloudfront.tf" 'Method Not Allowed' && has "$ROOT/cloudfront.tf" '405'); then
  ok 1.5 "9-1 HTTP Method Restriction (405)"
else
  bad 1.5 "9-1 HTTP Method Restriction"
fi

# 9-2 Query String 1.5
if has "$ROOT/cloudfront.tf" 'gj2026-waf-acl|gj2026-waf' \
  && has "$ROOT/cloudfront.tf" 'Access Denied' \
  && has "$ROOT/cloudfront.tf" '403' \
  && has "$ROOT/cloudfront.tf" 'client_id'; then
  ok 1.5 "9-2 Query String Restriction (403)"
else
  bad 1.5 "9-2 Query String Restriction"
fi

# ----- 10 Monitoring (3.0) -----
# 10-1 Fluent Bit 1.5
if has "$ROOT/k8s/fluentbit.yaml" 'aws-for-fluent-bit' \
  && has "$ROOT/k8s/fluentbit.yaml" '/eks/book-svc/access' \
  && has "$ROOT/k8s/fluentbit.yaml" 'ap-northeast-2a' \
  && has "$ROOT/k8s/fluentbit.yaml" 'ap-northeast-2b' \
  && has "$ROOT/k8s/fluentbit.yaml" 'remote_addr' \
  && has "$ROOT/k8s/fluentbit.yaml" 'namespace: logging' \
  && (has "$ROOT/k8s/fluentbit.yaml" 'STREAM_PLACEHOLDER|STREAM_NAME' || has "$ROOT/k8s/fluentbit.yaml" 'rewrite_tag'); then
  ok 1.5 "10-1 Fluent Bit (AZ streams)"
else
  bad 1.5 "10-1 Fluent Bit"
fi

# 10-2 Grafana 1.5
if has "$ROOT/post-deploy.sh" 'Skills53#' \
  && has "$ROOT/post-deploy.sh" 'namespace: monitoring' \
  && (has "$ROOT/k8s/dashboards/wsi-dashboard.json" 'WSI Dashboard' || has "$ROOT/post-deploy.sh" 'WSI Dashboard') \
  && has "$ROOT/lambda/handler.py" 'CloudWatchMetrics|EmbeddedMetric|client_id.*ALL|Namespace'; then
  ok 1.5 "10-2 Grafana Dashboard"
else
  bad 1.5 "10-2 Grafana Dashboard"
fi

PCT="$(awk -v s="$SCORE" 'BEGIN{printf "%.1f", (s/30.0)*100}')"
echo
echo "=== SCORE: ${SCORE} / 30.0  (${PCT}%)  missed=${MISS} ==="
awk -v s="$SCORE" 'BEGIN{exit !(s+0 >= 30.0)}'
