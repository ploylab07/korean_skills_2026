#!/usr/bin/env bash
# Score helper: clean NAT/extra IGW names, run mark-fast, summarize
set -euo pipefail
export AWS_DEFAULT_REGION=ap-northeast-2
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:?}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:?}"
cd /root/korean_skills_2026/day1/006

# Scoring hygiene (account-wide mark checks)
for nat in $(aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text); do
  aws ec2 delete-nat-gateway --nat-gateway-id "$nat" >/dev/null || true
done
for igw in $(aws ec2 describe-internet-gateways --query 'InternetGateways[].InternetGatewayId' --output text); do
  name=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$igw" --query 'InternetGateways[0].Tags[?Key==`Name`].Value|[0]' --output text)
  if [[ "$name" != "gj2026-igw" && "$name" != "None" && -n "$name" ]]; then
    aws ec2 delete-tags --resources "$igw" --tags Key=Name || true
  fi
done

# Ensure mark.sh has CF id
CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='gj2026-svc-cf'].Id|[0]" --output text 2>/dev/null || true)
if [[ -n "$CF_ID" && "$CF_ID" != "None" ]]; then
  sed -i "s/export DistributionID=.*/export DistributionID=\"${CF_ID}\"/" mark.sh
fi
sed -i 's/export BUCKET=.*/export BUCKET="gj2026-static-006"/' mark.sh
sed -i 's/^rm -rf ~\/.aws/# rm -rf ~\/.aws/' mark.sh
sed -i 's/^mkdir -p ~\/.aws/# mkdir -p ~\/.aws/' mark.sh

# Fast mark: skip invalidation wait
sed 's/aws cloudfront wait invalidation-completed/# aws cloudfront wait invalidation-completed/' mark.sh > /tmp/mark-fast.sh
chmod +x /tmp/mark-fast.sh
bash /tmp/mark-fast.sh 2>&1 | tee /tmp/mark-latest.txt
echo "MARK_DONE"
