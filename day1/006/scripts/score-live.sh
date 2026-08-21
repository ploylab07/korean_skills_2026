#!/usr/bin/env bash
# Score live mark.sh output against expected patterns (30 = 100%).
set -euo pipefail
MARK_LOG="${1:-/tmp/mark-live-final.txt}"
SCORE=0
MISS=0
ok()  { local p="$1"; shift; echo "[PASS +${p}] $*"; SCORE="$(awk -v a="$SCORE" -v b="$p" 'BEGIN{printf "%.1f", a+b}')"; }
bad() { local p="$1"; shift; echo "[FAIL -${p}] $*"; MISS="$(awk -v a="$MISS" -v b="$p" 'BEGIN{printf "%.1f", a+b}')"; }
has() { grep -qE "$2" "$MARK_LOG" 2>/dev/null; }
sec() { awk -v s="$1" '$0~s{p=1;next} p&&/^============/{exit} p' "$MARK_LOG"; }

echo "=== live mark score: $MARK_LOG ==="
[[ -f "$MARK_LOG" ]] || { echo "missing $MARK_LOG"; exit 1; }

# 1 Network 3.0
sec '1-1-A' | grep -q '10.0.0.0/16' && sec '1-1-A' | grep -q '10.0.10.0/24' && sec '1-1-A' | grep -q '10.0.11.0/24' \
  && ok 1.0 "1-1 VPC" || bad 1.0 "1-1 VPC"
sec '1-2-A' | grep -q 'gj2026-private-rtb-a' && sec '1-2-A' | grep -q '10.0.0.0/16' && ! sec '1-2-A' | grep -q '0.0.0.0/0' \
  && ok 1.0 "1-2 RT" || bad 1.0 "1-2 RT"
sec '1-3-A' | head -1 | grep -q '^0$' && sec '1-3-A' | grep -q 'gj2026-igw' \
  && ok 1.0 "1-3 NAT/IGW" || bad 1.0 "1-3 NAT/IGW"

# 2 ECR 2.5
sec '2-1-A' | grep -q '^book$' && ok 1.0 "2-1 ECR" || bad 1.0 "2-1 ECR"
sz=$(sec '2-2-A' | grep -Eo '[0-9]+\.[0-9]+mb' | head -1 | tr -d 'mb')
awk -v s="${sz:-9}" 'BEGIN{exit !(s+0<=3.0)}' && ok 1.5 "2-2 size ${sz}mb" || bad 1.5 "2-2 size"

# 3 DDB 2.5
sec '3-1-A' | grep -q 'booking_id' && sec '3-1-A' | grep -q 'client_id-index' \
  && ok 1.0 "3-1 DDB" || bad 1.0 "3-1 DDB"
sec '3-2-A' | grep -q 'alias/gj2026-db-key' && ok 0.5 "3-2 KMS" || bad 0.5 "3-2 KMS"
sec '3-3-A' | grep -qi 'AccessDeniedException' && ok 1.0 "3-3 Deny" || bad 1.0 "3-3 Deny"

# 4 EKS 6.5
sec '4-1-A' | grep -q 'gj2026-eks-cluster' && sec '4-1-A' | grep -q '1.35' && sec '4-1-A' | grep -q 'alias/gj2026-eks-key' \
  && ok 1.0 "4-1 EKS" || bad 1.0 "4-1 EKS"
sec '4-2-A' | grep -q 'BOTTLEROCKET' && sec '4-2-A' | grep -q 't3.medium' && sec '4-2-A' | grep -q 'm5.large' \
  && ok 1.5 "4-2 NG" || bad 1.5 "4-2 NG"
n=$(sec '4-3-A' | grep -cE '^gj2026\.i-[0-9a-f]+\.(addon|app)\.node$' || true)
[ "$n" -ge 4 ] && ok 1.5 "4-3 names ($n)" || bad 1.5 "4-3 names ($n)"
sec '4-4-A' | grep -qE 'book.*2/2|2[[:space:]]+2[[:space:]]+2' && ok 1.0 "4-4 book" || bad 1.0 "4-4 book"
sec '4-5-A' | grep -qE 'curl: \(28\)|Connection timed out' && ok 1.5 "4-5 NP" || bad 1.5 "4-5 NP"

# 5 ALB 1.0
sec '5-1-A' | grep -qi 'internal' && sec '5-1-A' | grep -q 'gj2026-vpc' \
  && ok 1.0 "5-1 ALB" || bad 1.0 "5-1 ALB"

# 6 S3 2.0
sec '6-1-A' | grep -q 'index.html' && sec '6-1-A' | grep -q 'main.jpeg' \
  && ok 1.0 "6-1 S3" || bad 1.0 "6-1 S3"
sec '6-2-A' | grep -q 'alias/gj2026-s3-key' && ok 1.0 "6-2 S3 KMS" || bad 1.0 "6-2 S3 KMS"

# 7 Lambda 1.0
sec '7-1-A' | grep -q 'gj2026-book-reservation' && sec '7-1-A' | grep -q 'python3.14' \
  && ok 1.0 "7-1 Lambda" || bad 1.0 "7-1 Lambda"

# 8 CDN 5.5
sec '8-1-A' | grep -q '200' && sec '8-1-A' | grep -qi 'cloudfront' \
  && ok 1.0 "8-1 static" || bad 1.0 "8-1 static"
sec '8-2-A' | grep -q 'booking_id' && ok 1.5 "8-2 POST" || bad 1.5 "8-2 POST"
sec '8-3-A' | grep -q 'Alice' && sec '8-3-A' | grep -q 'Bob' && ! sec '8-3-A' | grep -q 'David' \
  && ok 1.5 "8-3 reservation" || bad 1.5 "8-3 reservation"
sec '8-4-A' | grep -q 'Alice' && ok 1.5 "8-4 client_id" || bad 1.5 "8-4 client_id"

# 9 WAF 3.0
sec '9-1-A' | grep -q '405' && ok 1.5 "9-1 method" || bad 1.5 "9-1 method"
sec '9-2-A' | grep -q '403' && ok 1.5 "9-2 query" || bad 1.5 "9-2 query"

# 10 Observability 3.0
sec '10-1-A' | grep -q 'ap-northeast-2a' && sec '10-1-A' | grep -q 'ap-northeast-2b' \
  && ok 1.5 "10-1 fluent" || bad 1.5 "10-1 fluent"
sec '10-2-A' | grep -q '/grafana' && ok 1.5 "10-2 grafana" || bad 1.5 "10-2 grafana"

echo
echo "=== LIVE SCORE: ${SCORE} / 30.0  missed=${MISS} ==="
awk -v s="$SCORE" 'BEGIN{exit !(s+0>=30.0)}'
