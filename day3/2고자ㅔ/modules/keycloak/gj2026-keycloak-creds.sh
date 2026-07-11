#!/bin/bash
set -euo pipefail
TEAM="${1:-dev}"
USER="${2:-dev-user}"

# Load repo .env if present (for base AWS creds used by assume-role call)
ROOT="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
if [[ -f "$ROOT/build/load-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/build/load-env.sh"
  load_repo_env "$ROOT/build"
elif [[ -f /root/projects/korean_skills_2026/build/load-env.sh ]]; then
  # shellcheck disable=SC1091
  source /root/projects/korean_skills_2026/build/load-env.sh
  load_repo_env /root/projects/korean_skills_2026/build
fi

IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=gj2026-keycloak-ec2" "Name=instance-state-name,Values=running" \
  --region eu-central-1 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

if [[ -z "$IP" || "$IP" == "None" ]]; then
  echo "keycloak EC2 IP not found" >&2
  exit 1
fi

HOST="${IP//./-}.sslip.io"

case "$TEAM" in
  dev) CLIENT="gj2026-keycloak-dev" ;;
  sec) CLIENT="gj2026-keycloak-sec" ;;
  *) echo "unknown team: $TEAM" >&2; exit 1 ;;
esac

case "$USER" in
  dev-user|dev-user2) PASS='dev123!' ;;
  sec-user) PASS='sec123!' ;;
  *) PASS='dev123!' ;;
esac

# Prefer sslip.io (OIDC issuer). Fall back to IP for token if needed.
TOKEN=$(curl -sk -X POST "https://${HOST}/realms/team/protocol/openid-connect/token" \
  -d "client_id=${CLIENT}" -d "username=${USER}" -d "password=${PASS}" \
  -d "grant_type=password" -d "scope=openid" | jq -r '.id_token // empty')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  TOKEN=$(curl -sk -X POST "https://${IP}/realms/team/protocol/openid-connect/token" \
    -d "client_id=${CLIENT}" -d "username=${USER}" -d "password=${PASS}" \
    -d "grant_type=password" -d "scope=openid" | jq -r '.id_token // empty')
fi

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "failed to obtain id_token" >&2
  exit 1
fi

ROLE_ARN=$(aws iam list-roles \
  --query "Roles[?RoleName=='gj2026-keycloak-${TEAM}-role'].Arn" \
  --output text)

CREDS=$(aws sts assume-role-with-web-identity \
  --role-arn "$ROLE_ARN" \
  --role-session-name keycloak-session \
  --web-identity-token "$TOKEN")

cat <<JSON
{
  "Version": 1,
  "AccessKeyId": $(echo "$CREDS" | jq -r '.Credentials.AccessKeyId' | jq -R .),
  "SecretAccessKey": $(echo "$CREDS" | jq -r '.Credentials.SecretAccessKey' | jq -R .),
  "SessionToken": $(echo "$CREDS" | jq -r '.Credentials.SessionToken' | jq -R .),
  "Expiration": $(echo "$CREDS" | jq -r '.Credentials.Expiration' | jq -R .)
}
JSON
