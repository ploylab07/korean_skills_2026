#!/usr/bin/env bash
# On agent stop: remind harness verification if terraform files exist in repo
set -euo pipefail

input=$(cat)
status=$(echo "$input" | jq -r '.status // empty')

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if find "$root" -name '*.tf' -not -path '*/.terraform/*' -not -path '*/build/smoke/*' 2>/dev/null | grep -q .; then
  cat <<'EOF'
{
  "followup_message": "Terraform 작업이 있었습니다. 완료 전에 반드시 실행하세요: ./build/verify.sh && ./terraform -chdir=<과제폴더> plan. 채점 기준 대조도 잊지 마세요."
}
EOF
else
  cat <<'EOF'
{
  "followup_message": "작업 종료 전 ./build/verify.sh 로 래퍼·환경이 정상인지 확인하세요."
}
EOF
fi
