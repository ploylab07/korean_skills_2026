#!/bin/bash
# Bottlerocket bootstrap: set kubelet hostname before join
set -euo pipefail
ROLE=$(cat /.bottlerocket/bootstrap-containers/current/user-data 2>/dev/null || echo app)
# IMDS
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
if [[ -n "${TOKEN}" ]]; then
  IID=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" http://169.254.169.254/latest/meta-data/instance-id)
else
  IID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
fi
NAME="gj2026.${IID}.${ROLE}.node"
echo "Setting hostname to ${NAME}"
# Bottlerocket API unix socket
SOCKET=/.bottlerocket/api.sock
if [[ ! -S "$SOCKET" ]]; then
  SOCKET=/run/api.sock
fi
curl -s -X PATCH -H "Content-Type: application/json" \
  --unix-socket "$SOCKET" \
  -d "{\"kubernetes\":{\"hostname-override\":\"${NAME}\"},\"network\":{\"hostname\":\"${NAME}\"}}" \
  http://localhost/settings
echo "Done setting ${NAME}"
