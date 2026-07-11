#!/usr/bin/env bash
# 원클릭 전체 배포: GitHub 레포 생성 → Terraform apply → EKS/K8s → DB 초기화
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
GITHUB_REPO="${GITHUB_REPO:-gj2025-repository}"
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN 환경변수가 필요합니다}"

# shellcheck source=../../build/load-env.sh
source "$ROOT/build/load-env.sh"
load_repo_env "$ROOT/build"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

install_tools() {
  command -v jq >/dev/null || { apt-get update -qq && apt-get install -y -qq jq; }
  command -v envsubst >/dev/null || apt-get install -y -qq gettext-base
  if ! command -v kubectl >/dev/null; then
    log "kubectl 설치"
    curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
  fi
  if ! command -v helm >/dev/null; then
    log "helm 설치"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
}

setup_github() {
  log "GitHub 사용자 확인"
  GITHUB_OWNER=$(curl -fsS -H "Authorization: token ${GITHUB_TOKEN}" https://api.github.com/user | jq -r .login)
  log "GitHub owner: ${GITHUB_OWNER}"

  log "GitHub 레포지토리 생성 (${GITHUB_REPO})"
  HTTP=$(curl -sS -o /tmp/gh_create.json -w '%{http_code}' \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -X POST "https://api.github.com/user/repos" \
    -d "{\"name\":\"${GITHUB_REPO}\",\"private\":false,\"auto_init\":true}")
  if [[ "$HTTP" == "201" ]]; then
    log "레포지토리 생성 완료"
  elif [[ "$HTTP" == "422" ]]; then
    log "레포지토리가 이미 존재함 — 계속 진행"
  else
    cat /tmp/gh_create.json
    exit 1
  fi

  log "terraform.tfvars 생성"
  cat > "${DIR}/terraform.tfvars" <<EOF
github_owner       = "${GITHUB_OWNER}"
github_repo        = "${GITHUB_REPO}"
github_token       = "${GITHUB_TOKEN}"
github_oauth_token = "${GITHUB_TOKEN}"
EOF
  chmod 600 "${DIR}/terraform.tfvars"
}

terraform_apply() {
  log "Terraform init"
  "$TF" -chdir="$DIR" init -input=false -upgrade

  log "Terraform plan"
  "$TF" -chdir="$DIR" plan -input=false -out="${DIR}/tfplan"

  log "Terraform apply (30~60분 소요)"
  "$TF" -chdir="$DIR" apply -input=false -auto-approve "${DIR}/tfplan"
}

wait_bastion() {
  log "Bastion 준비 대기"
  local ip id i
  ip=$("$TF" -chdir="$DIR" output -raw bastion_public_ip)
  id=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=gj2025-bastion" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)

  aws ssm wait instance-online --instance-id "$id" --region "$REGION" 2>/dev/null || true

  for i in $(seq 1 40); do
    STATUS=$(aws ssm describe-instance-information --region "$REGION" \
      --filters "Key=InstanceIds,Values=${id}" \
      --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "Unknown")
    if [[ "$STATUS" == "Online" ]]; then
      log "Bastion SSM Online"
      return 0
    fi
    sleep 15
  done
  log "SSM 대기 시간 초과 — SSH로 계속 시도"
}

init_database() {
  log "RDS Proxy 경유 DB 초기화"
  local id proxy
  proxy=$("$TF" -chdir="$DIR" output -raw rds_proxy_endpoint)
  id=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=gj2025-bastion" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)

  aws ssm send-command --region "$REGION" --instance-ids "$id" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[
      'sleep 30',
      'mysql -h ${proxy} -P 3306 -u admin -pSkills53#\$% -e \"SELECT 1\" && mysql -h ${proxy} -P 3306 -u admin -pSkills53#\$% < /tmp/day1_table_v1.sql && echo DB_INIT_OK'
    ]" \
    --output text --query 'Command.CommandId' > /tmp/db_cmd_id

  local cmd_id
  cmd_id=$(cat /tmp/db_cmd_id)
  for i in $(seq 1 30); do
    if aws ssm get-command-invocation --region "$REGION" --command-id "$cmd_id" --instance-id "$id" \
      --query 'StandardOutputContent' --output text 2>/dev/null | grep -q DB_INIT_OK; then
      log "DB 초기화 완료"
      return 0
    fi
    sleep 10
  done
  log "DB 초기화 대기 중 (Bastion user-data에서도 시도됨)"
}

main() {
  log "=== gj2025 원클릭 배포 시작 ==="
  install_tools
  setup_github
  terraform_apply
  log "Bastion SSH 키 저장"
  aws ssm get-parameter --region "$REGION" --name "/gj2025/bastion/private-key" --with-decryption \
    --query 'Parameter.Value' --output text > "${DIR}/bastion.pem"
  chmod 600 "${DIR}/bastion.pem"

  bash "${DIR}/scripts/post-deploy-k8s.sh"
  wait_bastion
  init_database

  log "=== 검증 ==="
  "$ROOT/build/verify.sh"
  "$TF" -chdir="$DIR" plan -input=false >/dev/null && log "terraform plan: OK" || log "terraform plan: 확인 필요"

  ip=$("$TF" -chdir="$DIR" output -raw bastion_public_ip)
  nlb=$("$TF" -chdir="$DIR" output -raw app_external_nlb_dns)
  log "=== 배포 완료 ==="
  log "Bastion: ssh -i bastion.pem -p 2222 ec2-user@${ip}"
  log "API 테스트: curl http://${nlb}/red"
  log "채점: ssh 후 ./marking.sh"
}

main "$@"
