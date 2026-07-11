#!/bin/bash
set -euxo pipefail

dnf install -y java-17-amazon-corretto-headless wget tar gzip openssl jq aws-cli amazon-ssm-agent
systemctl enable --now amazon-ssm-agent

get_ip() {
  local token
  token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  curl -s -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/public-ipv4
}

IP=$(get_ip)
[ -n "$IP" ]
HOSTNAME="$(echo "$IP" | tr '.' '-')".sslip.io

KEYCLOAK_VERSION="26.0.7"
cd /opt
curl -fsSLO "https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz"
tar -xzf "keycloak-${KEYCLOAK_VERSION}.tar.gz"
ln -sfn "/opt/keycloak-${KEYCLOAK_VERSION}" /opt/keycloak

mkdir -p /opt/keycloak/certs
# Cert SAN covers both sslip.io hostname (OIDC) and raw IP (scoring script)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/keycloak/certs/key.pem -out /opt/keycloak/certs/cert.pem \
  -subj "/CN=${HOSTNAME}/O=GJ2026/C=KR" \
  -addext "subjectAltName=DNS:${HOSTNAME},IP:${IP}"

/opt/keycloak/bin/kc.sh build

cat > /usr/local/bin/start-keycloak.sh <<'START'
#!/bin/bash
set -euo pipefail
get_ip() {
  local token
  token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  curl -s -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/public-ipv4
}
IP=$(get_ip)
HOSTNAME="$(echo "$IP" | tr '.' '-')".sslip.io
# hostname=sslip.io for OIDC issuer; hostname-strict=false so scoring via IP works
exec /opt/keycloak/bin/kc.sh start \
  --https-certificate-file=/opt/keycloak/certs/cert.pem \
  --https-certificate-key-file=/opt/keycloak/certs/key.pem \
  --hostname="$HOSTNAME" \
  --hostname-strict=false \
  --http-enabled=false \
  --https-port=443
START
chmod +x /usr/local/bin/start-keycloak.sh

cat > /etc/systemd/system/keycloak.service <<'UNIT'
[Unit]
Description=Keycloak
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=KEYCLOAK_ADMIN=admin
Environment=KEYCLOAK_ADMIN_PASSWORD=admin1234!
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=admin
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=admin1234!
ExecStart=/usr/local/bin/start-keycloak.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now keycloak

# Wait until master realm responds on both hostname and IP
for i in $(seq 1 90); do
  curl -sk "https://${HOSTNAME}/realms/master" >/dev/null 2>&1 && break
  curl -sk "https://${IP}/realms/master" >/dev/null 2>&1 && break
  sleep 5
done

# Prefer IP for admin setup so it matches scoring script access pattern
ADMIN_BASE="https://${IP}"
ADMIN_TOKEN=$(curl -sk -X POST \
  "${ADMIN_BASE}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" -d "username=admin" -d "password=admin1234!" \
  -d "grant_type=password" | jq -r '.access_token')
[ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != "null" ]
H="Authorization: Bearer ${ADMIN_TOKEN}"
B="${ADMIN_BASE}/admin/realms/team"

curl -sk -X POST "${ADMIN_BASE}/admin/realms" \
  -H "$H" -H "Content-Type: application/json" \
  -d '{"realm":"team","enabled":true,"sslRequired":"external"}'

for g in dev-team sec-team; do
  curl -sk -X POST "$B/groups" -H "$H" -H "Content-Type: application/json" \
    -d "{\"name\":\"$g\"}"
done

curl -sk -X POST "$B/users" -H "$H" -H "Content-Type: application/json" \
  -d '{"username":"dev-user","enabled":true,"emailVerified":true,"firstName":"dev","lastName":"user","email":"dev-user@example.com","attributes":{"role":["developer"],"team":["dev-team"],"group":["dev-team"]}}'
DEV_UID=$(curl -sk -H "$H" "$B/users?username=dev-user" | jq -r '.[0].id')
curl -sk -X PUT "$B/users/${DEV_UID}/reset-password" -H "$H" -H "Content-Type: application/json" \
  -d '{"type":"password","value":"dev123!","temporary":false}'
DEV_GID=$(curl -sk -H "$H" "$B/groups" | jq -r '.[] | select(.name=="dev-team") | .id')
curl -sk -X PUT "$B/users/${DEV_UID}/groups/${DEV_GID}" -H "$H"

curl -sk -X POST "$B/users" -H "$H" -H "Content-Type: application/json" \
  -d '{"username":"sec-user","enabled":true,"emailVerified":true,"firstName":"sec","lastName":"user","email":"sec-user@example.com","attributes":{"role":["security"],"team":["sec-team"],"group":["sec-team"]}}'
SEC_UID=$(curl -sk -H "$H" "$B/users?username=sec-user" | jq -r '.[0].id')
curl -sk -X PUT "$B/users/${SEC_UID}/reset-password" -H "$H" -H "Content-Type: application/json" \
  -d '{"type":"password","value":"sec123!","temporary":false}'
SEC_GID=$(curl -sk -H "$H" "$B/groups" | jq -r '.[] | select(.name=="sec-team") | .id')
curl -sk -X PUT "$B/users/${SEC_UID}/groups/${SEC_GID}" -H "$H"

SCOPE_ID=$(curl -sk -X POST "$B/client-scopes" -H "$H" -H "Content-Type: application/json" \
  -d '{"name":"gj2026-keycloak-claims","protocol":"openid-connect"}' -w '%{http_code}' -o /tmp/scope.json)
# Location header may contain id; fall back to list
SCOPE_ID=$(curl -sk -H "$H" "$B/client-scopes" | jq -r '.[] | select(.name=="gj2026-keycloak-claims") | .id')

for name in role team group; do
  curl -sk -X POST "$B/client-scopes/${SCOPE_ID}/protocol-mappers/models" \
    -H "$H" -H "Content-Type: application/json" \
    -d "{\"name\":\"claim-${name}\",\"protocol\":\"openid-connect\",\"protocolMapper\":\"oidc-usermodel-attribute-mapper\",\"config\":{\"user.attribute\":\"${name}\",\"claim.name\":\"${name}\",\"jsonType.label\":\"String\",\"id.token.claim\":\"true\",\"access.token.claim\":\"true\",\"userinfo.token.claim\":\"true\",\"multivalued\":\"false\"}}" \
    >/dev/null || true
done

for CID in gj2026-keycloak-dev gj2026-keycloak-sec; do
  curl -sk -X POST "$B/clients" -H "$H" -H "Content-Type: application/json" \
    -d "{\"clientId\":\"${CID}\",\"enabled\":true,\"publicClient\":true,\"directAccessGrantsEnabled\":true,\"standardFlowEnabled\":true,\"redirectUris\":[\"*\"],\"webOrigins\":[\"*\"]}"
  CLIENT_ID=$(curl -sk -H "$H" "$B/clients?clientId=${CID}" | jq -r '.[0].id')
  curl -sk -X PUT "$B/clients/${CLIENT_ID}/default-client-scopes/${SCOPE_ID}" -H "$H" >/dev/null || true
done

# Also update OIDC thumbprint from the instance itself (best-effort)
THUMB=$(openssl x509 -in /opt/keycloak/certs/cert.pem -fingerprint -sha1 -noout \
  | awk -F= '{print tolower($2)}' | tr -d ':')
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn \
  "$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, \`${HOSTNAME}\`)].Arn | [0]" --output text)" \
  --thumbprint-list "$THUMB" 2>/dev/null || true

setup_aws_cli() {
  local home_dir="$1"
  mkdir -p "${home_dir}/.aws"
  cat > "${home_dir}/.aws/gj2026-keycloak-creds.sh" <<'CREDS'
#!/bin/bash
set -euo pipefail
TEAM="${1:-dev}"
USER="${2:-dev-user}"
get_ip() {
  local token
  token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  curl -s -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/public-ipv4
}
IP=$(get_ip)
HOSTNAME="$(echo "$IP" | tr '.' '-')".sslip.io
case "$TEAM" in
  dev) CLIENT="gj2026-keycloak-dev" ;;
  sec) CLIENT="gj2026-keycloak-sec" ;;
  *) echo "unknown team" >&2; exit 1 ;;
esac
case "$USER" in
  dev-user|dev-user2) PASS='dev123!' ;;
  sec-user) PASS='sec123!' ;;
  *) PASS='dev123!' ;;
esac
TOKEN=$(curl -sk -X POST "https://${HOSTNAME}/realms/team/protocol/openid-connect/token" \
  -d "client_id=${CLIENT}" -d "username=${USER}" -d "password=${PASS}" \
  -d "grant_type=password" -d "scope=openid" | jq -r .id_token)
ROLE_ARN=$(aws iam list-roles --query "Roles[?RoleName=='gj2026-keycloak-${TEAM}-role'].Arn" --output text)
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
CREDS
  chmod +x "${home_dir}/.aws/gj2026-keycloak-creds.sh"
  aws configure set credential_process "${home_dir}/.aws/gj2026-keycloak-creds.sh dev dev-user" --profile gj2026-keycloak-dev
  aws configure set region eu-central-1 --profile gj2026-keycloak-dev
  aws configure set credential_process "${home_dir}/.aws/gj2026-keycloak-creds.sh sec sec-user" --profile gj2026-keycloak-sec
  aws configure set region eu-central-1 --profile gj2026-keycloak-sec
  chown -R "$(stat -c '%U:%G' "$home_dir")" "${home_dir}/.aws" 2>/dev/null || true
}

setup_aws_cli /root
setup_aws_cli /home/ec2-user

echo "Keycloak setup complete"
