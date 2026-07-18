#!/usr/bin/env bash
# Run on an EC2 instance with wsc2026-kms-admin-role to repoint poisoned aliases.
set -euo pipefail
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"

declare -A KEY_MAP=(
  ["alias/wsc2026-db-kms"]="${DB_KEY_ID:?set DB_KEY_ID}"
  ["alias/wsc2026-ecr-kms"]="${ECR_KEY_ID:?set ECR_KEY_ID}"
  ["alias/wsc2026-eks-kms"]="${EKS_KEY_ID:?set EKS_KEY_ID}"
  ["alias/wsc2026-bucket-kms"]="${BUCKET_KEY_ID:?set BUCKET_KEY_ID}"
  ["alias/wsc2026-function-kms"]="${FUNCTION_KEY_ID:?set FUNCTION_KEY_ID}"
)

for alias in "${!KEY_MAP[@]}"; do
  target="${KEY_MAP[$alias]}"
  echo "Updating ${alias} -> ${target}"
  aws kms update-alias --alias-name "${alias}" --target-key-id "${target}" --region "${REGION}" \
    || aws kms create-alias --alias-name "${alias}" --target-key-id "${target}" --region "${REGION}"
done
