#!/usr/bin/env bash
# Static simulation: compare IaC files against 채점기준 (no live AWS required)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0; WARN=0
ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }
warn(){ echo "[WARN] $1"; WARN=$((WARN+1)); }
has() { grep -qE "$2" "$1" 2>/dev/null; }

echo "=== day1/002 score simulation (file-based) ==="
echo "root: $ROOT"
echo

# 1 Network
has "$ROOT/network.tf" 'cidr_block\s*=\s*"172.16.0.0/16"' && ok "1-1 VPC CIDR" || bad "1-1 VPC CIDR"
has "$ROOT/network.tf" 'wskorea26-pub-subnet-c' && has "$ROOT/network.tf" '172.16.1.0/24' && ok "1-1 pub-c" || bad "1-1 pub-c"
has "$ROOT/network.tf" 'wskorea26-priv-subnet-d' && has "$ROOT/network.tf" '172.16.202.0/24' && ok "1-1 priv-d" || bad "1-1 priv-d"
has "$ROOT/network.tf" 'book-igw' && has "$ROOT/network.tf" 'book-ngw-c' && has "$ROOT/network.tf" 'book-ngw-d' && ok "1-2 IGW/NAT names" || bad "1-2 IGW/NAT names"
has "$ROOT/network.tf" 'wskorea26-public-rtb' && has "$ROOT/network.tf" 'wskorea26-private-rtb-c' && ok "1-2 RTB names" || bad "1-2 RTB names"

# 2 S3
has "$ROOT/locals.tf" 'wskorea26-concert-bucket-' && ok "2-1 bucket name pattern" || bad "2-1 bucket"
has "$ROOT/s3.tf" 'web/main/index.html' && has "$ROOT/s3.tf" 'web/main/main.jpeg' && ok "2-1 object paths" || bad "2-1 objects"
has "$ROOT/kms.tf" 'wskorea26-s3-key' && has "$ROOT/s3.tf" 'aws_kms_key.s3' && ok "2-2 KMS alias" || bad "2-2 KMS"
has "$ROOT/s3.tf" 'block_public_acls\s*=\s*true' && ok "2-2 public access block" || bad "2-2 PAB"

# 3 ECR
has "$ROOT/storage.tf" 'wskorea26-book-repo' && has "$ROOT/storage.tf" 'scan_on_push\s*=\s*true' && has "$ROOT/storage.tf" 'encryption_type\s*=\s*"KMS"' && ok "3-1 ECR scan+KMS" || bad "3-1 ECR"
has "$ROOT/storage.tf" ':stable' && ok "3-1 image tag stable" || bad "3-1 tag"

# 4 DDB
has "$ROOT/storage.tf" 'wskorea26-data-table' && has "$ROOT/storage.tf" 'hash_key\s*=\s*"client_id"' && has "$ROOT/storage.tf" 'deletion_protection_enabled\s*=\s*true' && ok "4-1 DDB" || bad "4-1 DDB"
has "$ROOT/kms.tf" 'wskorea26-dynamodb-key' && ok "4-1 DDB KMS alias" || bad "4-1 DDB KMS"

# 5 EKS
has "$ROOT/eks.tf" 'version\s*=\s*"1.35"' && ok "5-1 version 1.35" || bad "5-1 version"
has "$ROOT/eks.tf" 'api".*"audit".*"authenticator"|enabled_cluster_log_types' && ok "5-1 logging present" || bad "5-1 logging"
has "$ROOT/kms.tf" 'wskorea26-eks-key' && ok "5-2 EKS KMS" || bad "5-2 KMS"
has "$ROOT/eks.tf" 'aws_subnet.priv_c' && has "$ROOT/eks.tf" 'aws_subnet.priv_d' && ok "5-2 private subnets" || bad "5-2 subnets"

# 5-3 instance Name tags (problem: Node Instance Tag)
if has "$ROOT/eks.tf" 'Name = "wskorea26-addon-node"' && has "$ROOT/eks.tf" 'Name = "wskorea26-app-node"'; then
  if has "$ROOT/eks.tf" 'Name = "wskorea26-node"'; then
    bad "5-3 LT still has generic Name=wskorea26-node (instances must be addon-node / app-node)"
  else
    ok "5-3 distinct instance Name tags"
  fi
else
  # NG tags alone are not enough per problem text
  if grep -A2 'tags = {' "$ROOT/eks.tf" | grep -q 'wskorea26-addon-node'; then
    warn "5-3 NG tags set but LT instance Name may be wrong"
  else
    bad "5-3 missing addon/app Name tags"
  fi
fi
has "$ROOT/eks.tf" 'wskorea26-addon-ng' && has "$ROOT/eks.tf" 't3.medium' && has "$ROOT/eks.tf" 'wskorea26-app-ng' && ok "5-3 NG names/types" || bad "5-3 NG"

# 5-4 pods
has "$ROOT/k8s.tf" 'name = "wskorea26"' && has "$ROOT/k8s.tf" '"node-type" = "app"' && ok "5-4 book on app" || bad "5-4 book"
if has "$ROOT/eks.tf" 'pin_kube_system_to_addon|pod-identity-agent'; then
  ok "5-4 kube-system pinned to addon"
else
  warn "5-4 eks-pod-identity-agent not patched — runs on app nodes → mark 5-4 can print addon+app twice"
fi

# 6 Lambda
has "$ROOT/lambda.tf" 'python3.14' && has "$ROOT/lambda.tf" 'wskorea26-book-lambda' && ok "6-1 runtime/name" || bad "6-1 lambda"
has "$ROOT/lambda/lambda_function.py" 'ScanIndexForward=False' && has "$ROOT/lambda/lambda_function.py" 'timedelta\(hours=9\)' && ok "6/9 Lambda KST+sort" || bad "6/9 Lambda logic"

# 7 ALB
has "$ROOT/alb.tf" 'wskorea26-book-alb' && has "$ROOT/alb.tf" 'internal\s*=\s*false' && ok "7-1 ALB" || bad "7-1"
has "$ROOT/alb.tf" 'X-Origin-Verify' && has "$ROOT/alb.tf" 'status_code\s*=\s*"403"' && ok "7-2 header+403" || bad "7-2"

# 8 CF
has "$ROOT/cloudfront.tf" 'wskorea26-concert-cf' && has "$ROOT/cloudfront.tf" 'PriceClass_All' && ok "8-1 CF comment/price" || bad "8-1"
has "$ROOT/cloudfront.tf" 'wskorea26-alb-origin' && has "$ROOT/cloudfront.tf" 'wskorea26-s3-origin' && ok "8-2 origins" || bad "8-2"
has "$ROOT/cloudfront.tf" 'redirect-to-https' && has "$ROOT/cloudfront.tf" '/book\*' && ok "8-3 behaviors" || bad "8-3"
has "$ROOT/cloudfront.tf" 'wskorea26-s3-access' && has "$ROOT/cloudfront.tf" 'wskorea26-cf' && ok "8-4 headers" || bad "8-4"
has "$ROOT/cloudfront.tf" 'default_root_object\s*=\s*"index.html"' && ok "8-5 root object" || bad "8-5"

# 9 App paths
has "$ROOT/cloudfront.tf" '/v1/book' && ok "9-1 POST rewrite /v1/book" || bad "9-1 rewrite"
has "$ROOT/alb.tf" 'aws_lb_target_group.lambda' && has "$ROOT/alb.tf" 'GET' && ok "9-2 GET→Lambda" || bad "9-2"

# 10 Monitoring — CRITICAL
if has "$ROOT/k8s.tf" 'prometheus.enabled".*"false|prometheus.enabled"\s*\n\s*value\s*=\s*"false"'; then
  bad "10-x prometheus.enabled=false → Grafana panels have no metrics (manual 감점)"
elif grep -A1 'name\s*=\s*"prometheus.enabled"' "$ROOT/k8s.tf" | grep -q 'false'; then
  bad "10-x prometheus.enabled=false → Grafana panels have no metrics (manual 감점)"
else
  ok "10-x prometheus enabled in TF"
fi
if grep -A1 'name\s*=\s*"prometheusOperator.enabled"' "$ROOT/k8s.tf" | grep -q 'false'; then
  bad "10-x prometheusOperator.enabled=false"
else
  ok "10-x prometheusOperator enabled"
fi
has "$ROOT/k8s/monitoring/dashboard.json" 'Container CPU Usage' \
  && has "$ROOT/k8s/monitoring/dashboard.json" 'Container Memory Usage' \
  && has "$ROOT/k8s/monitoring/dashboard.json" 'Running Pods' \
  && has "$ROOT/k8s/monitoring/dashboard.json" 'Container Restarts' \
  && has "$ROOT/k8s/monitoring/dashboard.json" 'Container Network Receive' \
  && ok "10 dashboard panels present" || bad "10 dashboard panels"
has "$ROOT/k8s/monitoring/dashboard.json" 'wskorea26-monitoring' && ok "10 dashboard title/uid" || bad "10 dashboard name"
has "$ROOT/locals.tf" 'skills-\${var.bibun}-admin' && ok "10 grafana user pattern" || bad "10 grafana user"
has "$ROOT/alb.tf" 'wskorea26-grafana-alb' && ok "10 grafana ALB" || bad "10 grafana ALB"

# Monitoring must stay on addon
if grep -A5 'prometheus-node-exporter' "$ROOT/k8s/monitoring/values.yaml" | grep -q 'operator: Exists'; then
  bad "10 node-exporter tolerates all taints → schedules on app NG (문제: monitoring은 addon만)"
else
  ok "10 node-exporter not globally tolerating (or unused values.yaml)"
fi

echo
echo "=== result: PASS=$PASS FAIL=$FAIL WARN=$WARN ==="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
