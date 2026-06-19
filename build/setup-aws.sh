#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

echo "AWS 자격 증명 설정"
echo "입력값은 $ENV_FILE 에 저장됩니다. (.gitignore 대상, Git에 올라가지 않음)"
echo

read -rp "AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
read -rsp "AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
echo
read -rp "AWS_DEFAULT_REGION [ap-northeast-2]: " AWS_DEFAULT_REGION
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"

if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "error: Access Key와 Secret Key는 필수입니다." >&2
  exit 1
fi

cat > "$ENV_FILE" <<EOF
# AWS credentials — do not commit
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
EOF

chmod 600 "$ENV_FILE"
echo
echo "저장 완료: $ENV_FILE"
echo "이제 ./terraform.cmd 또는 ./terraform 실행 시 자동으로 적용됩니다."
