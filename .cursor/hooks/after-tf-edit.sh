#!/usr/bin/env bash
# After .tf edit: suggest terraform validate in the edited file's directory
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.file_path // .path // empty')

if [[ -z "$file_path" || "$file_path" != *.tf ]]; then
  exit 0
fi

dir=$(dirname "$file_path")
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

cat <<EOF
{
  "additional_context": "Terraform 파일이 수정됨: ${file_path}. 과제 폴더에서 검증을 실행하세요: ./terraform -chdir=${dir} validate && ./terraform -chdir=${dir} plan. 완료 전 ./build/verify.sh 도 실행하세요."
}
EOF
