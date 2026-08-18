#!/usr/bin/env bash
set -euo pipefail
PROJECT="${TF_CB_PROJECT:?}"
REGION="${TF_CB_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-2}}"
echo "Starting CodeBuild: $PROJECT"
BUILD_ID=$(aws codebuild start-build --region "$REGION" --project-name "$PROJECT" --query 'build.id' --output text)
echo "Build id: $BUILD_ID"
for i in $(seq 1 90); do
  STATUS=$(aws codebuild batch-get-builds --region "$REGION" --ids "$BUILD_ID" --query 'builds[0].buildStatus' --output text)
  PHASE=$(aws codebuild batch-get-builds --region "$REGION" --ids "$BUILD_ID" --query 'builds[0].currentPhase' --output text)
  echo "[$i] status=$STATUS phase=$PHASE"
  case "$STATUS" in
    SUCCEEDED) echo "CodeBuild SUCCEEDED"; exit 0 ;;
    FAILED|FAULT|STOPPED|TIMED_OUT)
      echo "CodeBuild failed: $STATUS"
      aws codebuild batch-get-builds --region "$REGION" --ids "$BUILD_ID" --query 'builds[0].phases' --output json || true
      exit 1
      ;;
  esac
  sleep 10
done
echo "Timed out waiting for CodeBuild"
exit 1
