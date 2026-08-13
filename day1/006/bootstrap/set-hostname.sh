#!/bin/bash
set -euo pipefail
ROLE=$(cat /.bottlerocket/bootstrap-containers/current/user-data 2>/dev/null || echo app)
if [[ "$ROLE" != "addon" && "$ROLE" != "app" ]]; then
  ROLE=$(printf '%s' "$ROLE" | base64 -d 2>/dev/null || echo app)
fi
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
if [[ -n "${TOKEN}" ]]; then
  IID=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" http://169.254.169.254/latest/meta-data/instance-id)
else
  IID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
fi
[[ -n "$IID" ]] || { echo "no IID"; exit 1; }
NAME="gj2026.${IID}.${ROLE}.node"
echo "Setting hostname to ${NAME}"
SOCKET=/.bottlerocket/api.sock
[ -S "$SOCKET" ] || SOCKET=/run/api.sock
# Do not set hostname-override-source here (BR 1.63 only allows private-dns-name|instance-id)
curl -sf -X PATCH -H "Content-Type: application/json" --unix-socket "$SOCKET" \
  -d "{\"kubernetes\":{\"hostname-override\":\"${NAME}\"},\"network\":{\"hostname\":\"${NAME}\"}}" \
  http://localhost/settings
curl -sf -X POST --unix-socket "$SOCKET" http://localhost/tx/commit_and_apply || true
echo "Done ${NAME}"
