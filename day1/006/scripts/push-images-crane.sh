#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
aws ecr get-login-password --region "$REGION" | crane auth login --username AWS --password-stdin "$ECR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/book-linux-amd64_v1.0.1" "$TMP/book"
chmod +x "$TMP/book"
mkdir -p "$TMP/etc/ssl/certs" "$TMP/etc/pki/tls/certs"
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
  cp /etc/ssl/certs/ca-certificates.crt "$TMP/etc/ssl/certs/"
else
  curl -fsSL https://curl.se/ca/cacert.pem -o "$TMP/etc/ssl/certs/ca-certificates.crt"
fi
cp "$TMP/etc/ssl/certs/ca-certificates.crt" "$TMP/etc/pki/tls/certs/ca-bundle.crt"
tar -C "$TMP" -cf "$TMP/book-layer.tar" book etc
crane append --base="" -f "$TMP/book-layer.tar" -t "${ECR}/book:latest"
crane mutate "${ECR}/book:latest" --entrypoint=/book -t "${ECR}/book:latest"
echo "book pushed"
cp "$ROOT/bootstrap/set-hostname.sh" "$TMP/set-hostname.sh"
chmod +x "$TMP/set-hostname.sh"
tar -C "$TMP" -cf "$TMP/hb-layer.tar" set-hostname.sh
crane append -b public.ecr.aws/amazonlinux/amazonlinux:2023 -f "$TMP/hb-layer.tar" -t "${ECR}/hostname-bootstrap:latest"
crane mutate "${ECR}/hostname-bootstrap:latest" --entrypoint=/set-hostname.sh -t "${ECR}/hostname-bootstrap:latest"
echo "hostname-bootstrap pushed"
