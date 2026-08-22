#!/usr/bin/env bash
# File-based scoring simulation against day1_02_release_candidate_marking.pdf (total 27 = 100%)
# No live AWS required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCORE=0
MISS=0
ok()  { local pts="$1"; shift; echo "[PASS +${pts}] $*"; SCORE="$(awk -v a="$SCORE" -v b="$pts" 'BEGIN{printf "%.1f", a+b}')"; }
bad() { local pts="$1"; shift; echo "[FAIL -${pts}] $*"; MISS="$(awk -v a="$MISS" -v b="$pts" 'BEGIN{printf "%.1f", a+b}')"; }
has() { grep -qE "$2" "$1" 2>/dev/null; }

echo "=== day1/002 score simulation (RC 채점기준 27점 = 100%) ==="
echo "root: $ROOT"
echo

# ----- 1 Network Configuration (1.0) -----
# 1-1 Resources CIDR 0.5
if has "$ROOT/network.tf" 'cidr_block\s*=\s*"172.16.0.0/16"' \
  && has "$ROOT/network.tf" 'Name = "wskorea26-vpc"' \
  && has "$ROOT/network.tf" 'wskorea26-pub-subnet-c' && has "$ROOT/network.tf" '172.16.1.0/24' \
  && has "$ROOT/network.tf" 'wskorea26-pub-subnet-d' && has "$ROOT/network.tf" '172.16.2.0/24' \
  && has "$ROOT/network.tf" 'wskorea26-priv-subnet-c' && has "$ROOT/network.tf" '172.16.201.0/24' \
  && has "$ROOT/network.tf" 'wskorea26-priv-subnet-d' && has "$ROOT/network.tf" '172.16.202.0/24'; then
  ok 0.5 "1-1 Resources CIDR"
else
  bad 0.5 "1-1 Resources CIDR"
fi

# 1-2 Routing Tables 0.5
if has "$ROOT/network.tf" 'Name = "book-igw"' \
  && has "$ROOT/network.tf" 'Name = "book-ngw-c"' && has "$ROOT/network.tf" 'Name = "book-ngw-d"' \
  && has "$ROOT/network.tf" 'wskorea26-public-rtb' \
  && has "$ROOT/network.tf" 'wskorea26-private-rtb-c' && has "$ROOT/network.tf" 'wskorea26-private-rtb-d' \
  && has "$ROOT/network.tf" 'gateway_id\s*=\s*aws_internet_gateway.main.id' \
  && has "$ROOT/network.tf" 'nat_gateway_id\s*=\s*aws_nat_gateway.nat_c.id' \
  && has "$ROOT/network.tf" 'nat_gateway_id\s*=\s*aws_nat_gateway.nat_d.id'; then
  ok 0.5 "1-2 Routing Tables"
else
  bad 0.5 "1-2 Routing Tables"
fi

# ----- 2 S3 (2.0) -----
# 2-1 Bucket & Objects 1.0
if has "$ROOT/locals.tf" 'wskorea26-concert-bucket-' \
  && has "$ROOT/s3.tf" 'web/main/index.html' && has "$ROOT/s3.tf" 'web/main/main.jpeg' \
  && [[ "$(wc -c < "$ROOT/main.jpeg" | tr -d ' ')" == "180926" ]]; then
  ok 1.0 "2-1 S3 Bucket & Objects (main.jpeg=180926)"
else
  bad 1.0 "2-1 S3 Bucket & Objects"
fi

# 2-2 Configuration 1.0
if has "$ROOT/kms.tf" 'alias/wskorea26-s3-key' && has "$ROOT/s3.tf" 'aws_kms_key.s3' \
  && has "$ROOT/s3.tf" 'block_public_acls\s*=\s*true' \
  && has "$ROOT/s3.tf" 'ignore_public_acls\s*=\s*true' \
  && has "$ROOT/s3.tf" 'block_public_policy\s*=\s*true' \
  && has "$ROOT/s3.tf" 'restrict_public_buckets\s*=\s*true'; then
  ok 1.0 "2-2 S3 Configuration (KMS+PAB)"
else
  bad 1.0 "2-2 S3 Configuration"
fi

# ----- 3 ECR (1.0) -----
if has "$ROOT/storage.tf" 'wskorea26-book-repo' \
  && has "$ROOT/storage.tf" 'scan_on_push\s*=\s*true' \
  && has "$ROOT/storage.tf" 'encryption_type\s*=\s*"KMS"' \
  && has "$ROOT/storage.tf" ':stable' \
  && has "$ROOT/kms.tf" 'alias/wskorea26-ecr-key'; then
  ok 1.0 "3-1 ECR Repository & Image"
else
  bad 1.0 "3-1 ECR Repository & Image"
fi

# ----- 4 DynamoDB (1.0) -----
if has "$ROOT/storage.tf" 'wskorea26-data-table' \
  && has "$ROOT/storage.tf" 'hash_key\s*=\s*"client_id"' \
  && has "$ROOT/storage.tf" 'deletion_protection_enabled\s*=\s*true' \
  && has "$ROOT/storage.tf" 'concert_name-created_at-index' \
  && has "$ROOT/kms.tf" 'alias/wskorea26-dynamodb-key' \
  && has "$ROOT/storage.tf" 'aws_kms_key.dynamodb'; then
  ok 1.0 "4-1 DynamoDB Configuration (GSI+KMS)"
else
  bad 1.0 "4-1 DynamoDB Configuration"
fi

# ----- 5 EKS (5.0) -----
# 5-1 Cluster Configuration 1.0
if (has "$ROOT/eks.tf" 'local.cluster_name' || has "$ROOT/eks.tf" 'wskorea26-cluster') \
  && has "$ROOT/locals.tf" 'cluster_name\s*=\s*"wskorea26-cluster"' \
  && has "$ROOT/eks.tf" 'version\s*=\s*"1.35"' \
  && has "$ROOT/eks.tf" '"api"' && has "$ROOT/eks.tf" '"audit"' && has "$ROOT/eks.tf" '"authenticator"' \
  && has "$ROOT/eks.tf" '"controllerManager"' && has "$ROOT/eks.tf" '"scheduler"'; then
  ok 1.0 "5-1 Cluster Configuration"
else
  bad 1.0 "5-1 Cluster Configuration"
fi

# 5-2 Encryption & Networking 1.0
if has "$ROOT/kms.tf" 'alias/wskorea26-eks-key' \
  && has "$ROOT/eks.tf" 'aws_kms_key.eks' \
  && has "$ROOT/eks.tf" 'aws_subnet.priv_c' && has "$ROOT/eks.tf" 'aws_subnet.priv_d'; then
  ok 1.0 "5-2 Cluster Encryption & Networking"
else
  bad 1.0 "5-2 Cluster Encryption & Networking"
fi

# 5-3 Node Configuration 1.5 (RC: name+instanceType+priv subnets; Name tag은 문제요구로 유지)
if has "$ROOT/eks.tf" 'wskorea26-addon-ng' && has "$ROOT/eks.tf" 'wskorea26-app-ng' \
  && has "$ROOT/eks.tf" 't3.medium' \
  && has "$ROOT/eks.tf" 'Name = "wskorea26-addon-node"' \
  && has "$ROOT/eks.tf" 'Name = "wskorea26-app-node"' \
  && ! has "$ROOT/eks.tf" 'Name = "wskorea26-node"' \
  && grep -A20 'resource "aws_eks_node_group" "addon"' "$ROOT/eks.tf" | grep -q 'aws_subnet.priv_c' \
  && grep -A20 'resource "aws_eks_node_group" "app"' "$ROOT/eks.tf" | grep -q 'aws_subnet.priv_d'; then
  ok 1.5 "5-3 Cluster Node Configuration"
else
  bad 1.5 "5-3 Cluster Node Configuration"
fi

# 5-4 Pod Configuration 1.5
if has "$ROOT/k8s.tf" 'name = "wskorea26"' \
  && has "$ROOT/k8s.tf" '"node-type" = "app"' \
  && (has "$ROOT/eks.tf" 'pin_kube_system_to_addon' || has "$ROOT/eks.tf" 'pod-identity-agent') \
  && has "$ROOT/eks.tf" '"node-type" = "addon"' \
  && grep -A8 'taint' "$ROOT/eks.tf" | grep -q 'app'; then
  ok 1.5 "5-4 Cluster Pod Configuration"
else
  bad 1.5 "5-4 Cluster Pod Configuration"
fi

# ----- 6 Lambda (1.0) -----
if has "$ROOT/lambda.tf" 'wskorea26-book-lambda' && has "$ROOT/lambda.tf" 'python3.14' \
  && has "$ROOT/lambda.tf" 'TABLE_NAME' \
  && has "$ROOT/lambda/lambda_function.py" 'ScanIndexForward=False' \
  && has "$ROOT/lambda/lambda_function.py" 'timedelta\(hours=9\)' \
  && has "$ROOT/lambda/lambda_function.py" 'concert_name is required' \
  && has "$ROOT/lambda/lambda_function.py" 'booking_id'; then
  ok 1.0 "6-1 Function Configuration"
else
  bad 1.0 "6-1 Function Configuration"
fi

# ----- 7 Load Balancing (2.5) -----
# 7-1 ALB Configuration 1.0
if has "$ROOT/alb.tf" 'wskorea26-book-alb' && has "$ROOT/alb.tf" 'internal\s*=\s*false' \
  && has "$ROOT/alb.tf" 'port\s*=\s*80' && has "$ROOT/alb.tf" 'protocol\s*=\s*"HTTP"'; then
  ok 1.0 "7-1 ALB Configuration"
else
  bad 1.0 "7-1 ALB Configuration"
fi

# 7-2 ALB Rules 1.5
if has "$ROOT/alb.tf" 'X-Origin-Verify' && has "$ROOT/alb.tf" 'wskorea26-cf' \
  && has "$ROOT/alb.tf" 'status_code\s*=\s*"403"' \
  && has "$ROOT/alb.tf" 'aws_lb_target_group.book' \
  && has "$ROOT/alb.tf" 'aws_lb_target_group.lambda' \
  && has "$ROOT/alb.tf" '/reserv-query'; then
  ok 1.5 "7-2 ALB Rules Configuration (/reserv-query GET)"
else
  bad 1.5 "7-2 ALB Rules Configuration"
fi

# ----- 8 CloudFront (6.5) -----
# 8-1 Distribution 1.0
if has "$ROOT/cloudfront.tf" 'wskorea26-concert-cf' && has "$ROOT/cloudfront.tf" 'PriceClass_All'; then
  ok 1.0 "8-1 Distribution Configuration"
else
  bad 1.0 "8-1 Distribution Configuration"
fi

# 8-2 Origins 1.5
if has "$ROOT/cloudfront.tf" 'wskorea26-alb-origin' && has "$ROOT/cloudfront.tf" 'wskorea26-s3-origin'; then
  ok 1.5 "8-2 Origin Configuration"
else
  bad 1.5 "8-2 Origin Configuration"
fi

# 8-3 Behaviors 1.5 (/book* or /book → ALB; /reserv-query* → ALB)
if has "$ROOT/cloudfront.tf" 'redirect-to-https' \
  && (has "$ROOT/cloudfront.tf" '/book\*' || has "$ROOT/cloudfront.tf" 'path_pattern.*=.*"/book"') \
  && has "$ROOT/cloudfront.tf" '/reserv-query' \
  && grep -A6 'default_cache_behavior' "$ROOT/cloudfront.tf" | grep -q 'wskorea26-s3-origin' \
  && grep -A12 'ordered_cache_behavior' "$ROOT/cloudfront.tf" | grep -q 'wskorea26-alb-origin'; then
  ok 1.5 "8-3 Distribution Policy Configuration"
else
  bad 1.5 "8-3 Distribution Policy Configuration"
fi

# 8-4 Custom Headers 1.0
if has "$ROOT/cloudfront.tf" 'X-Origin-Verify' && has "$ROOT/cloudfront.tf" 'wskorea26-cf' \
  && has "$ROOT/cloudfront.tf" 'wskorea26-s3-access'; then
  ok 1.0 "8-4 Custom Headers"
else
  bad 1.0 "8-4 Custom Headers"
fi

# 8-5 Static Web Hosting 1.5
if has "$ROOT/cloudfront.tf" 'default_root_object\s*=\s*"index.html"' \
  && has "$ROOT/cloudfront.tf" 'redirect-to-https' \
  && [[ -f "$ROOT/index.html" ]] && [[ -f "$ROOT/main.jpeg" ]]; then
  ok 1.5 "8-5 Static Web Hosting"
else
  bad 1.5 "8-5 Static Web Hosting"
fi

# ----- 9 Application (6.0) -----
# 9-1 POST 1.5 — CF rewrite /book → /v1/book + ALB POST → book TG
if has "$ROOT/cloudfront.tf" '/v1/book' && has "$ROOT/alb.tf" 'POST' \
  && has "$ROOT/k8s.tf" 'TABLE_NAME' && has "$ROOT/k8s.tf" ':stable'; then
  ok 1.5 "9-1 Application POST (/book → /v1/book)"
else
  bad 1.5 "9-1 Application POST"
fi

# 9-2 GET 1.5 — RC marking: /reserv-query → Lambda
if has "$ROOT/alb.tf" 'aws_lb_target_group.lambda' \
  && has "$ROOT/alb.tf" '/reserv-query' \
  && grep -A25 'get_book\|get_reserv\|reserv-query' "$ROOT/alb.tf" | grep -q 'GET' \
  && has "$ROOT/lambda/lambda_function.py" 'ScanIndexForward=False' \
  && has "$ROOT/lambda/lambda_function.py" 'timedelta\(hours=9\)' \
  && has "$ROOT/lambda/lambda_function.py" 'booking_id'; then
  ok 1.5 "9-2 Application GET (/reserv-query)"
else
  bad 1.5 "9-2 Application GET"
fi

# 9-3 ERROR 1.5 — missing concert_name → 400 on /reserv-query
if has "$ROOT/lambda/lambda_function.py" 'concert_name is required' \
  && has "$ROOT/lambda/lambda_function.py" 'statusCode' \
  && has "$ROOT/d1-02-mark.sh" 'reserv-query'; then
  ok 1.5 "9-3 Application ERROR (400 /reserv-query)"
else
  bad 1.5 "9-3 Application ERROR"
fi

# 9-4 Operation 1.5 — env not hardcoded + ALB format response
if has "$ROOT/lambda.tf" 'TABLE_NAME\s*=\s*aws_dynamodb_table.data.name' \
  && has "$ROOT/lambda/lambda_function.py" 'os.environ\["TABLE_NAME"\]' \
  && has "$ROOT/lambda/lambda_function.py" 'statusCode' \
  && has "$ROOT/lambda/lambda_function.py" 'isBase64Encoded'; then
  ok 1.5 "9-4 Application Operation (ALB format, no hardcode)"
else
  bad 1.5 "9-4 Application Operation"
fi

# ----- 10 Monitoring (1.0) — RC: Grafana Dashboard Check only (book CPU) -----
if (has "$ROOT/k8s/monitoring/dashboard.json" 'Container CPU' \
     || has "$ROOT/k8s/monitoring/dashboard.json" 'CPU Utilization' \
     || has "$ROOT/k8s/monitoring/dashboard.json" 'Book.*CPU') \
  && has "$ROOT/k8s/monitoring/dashboard.json" '"wskorea26-monitoring"' \
  && has "$ROOT/k8s/monitoring/dashboard.json" '"uid": "wskorea26"' \
  && has "$ROOT/locals.tf" 'skills-\${var.bibun}-admin' \
  && has "$ROOT/alb.tf" 'wskorea26-grafana-alb'; then
  ok 1.0 "10-1 Grafana Dashboard Check (book CPU)"
else
  bad 1.0 "10-1 Grafana Dashboard Check"
fi

PCT="$(awk -v s="$SCORE" 'BEGIN{printf "%.1f", (s/27.0)*100}')"
echo
echo "=== SCORE: ${SCORE} / 27.0  (${PCT}%)  missed=${MISS} ==="
awk -v s="$SCORE" 'BEGIN{exit !(s+0 >= 27.0)}'
