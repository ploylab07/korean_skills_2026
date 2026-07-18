#!/bin/bash
# Deploy Module1 Workflow - ap-southeast-1
set -euo pipefail

REGION="ap-southeast-1"
NUM="${NUM:-001}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="wsc2026-student-score-bucket-${NUM}"
BASE="/root/korean_skills_2026/day2/002/module1"
WORK="/tmp/m1-deploy"
mkdir -p "$WORK"

export AWS_DEFAULT_REGION="$REGION"
aws configure set region "$REGION"

echo "=== Module1 deploy: account=$ACCOUNT_ID bucket=$BUCKET ==="

# --- S3 ---
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi
# folders via placeholder objects
: > "$WORK/empty"
for p in input/ processed/ error/; do
  aws s3api put-object --bucket "$BUCKET" --key "$p" --body "$WORK/empty" 2>/dev/null || true
done
# Clear processed/error for clean grading state later
aws s3 rm "s3://$BUCKET/processed/" --recursive 2>/dev/null || true
aws s3 rm "s3://$BUCKET/error/" --recursive 2>/dev/null || true

# --- DynamoDB ---
if ! aws dynamodb describe-table --table-name wsc2026-student-score >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name wsc2026-student-score \
    --attribute-definitions \
      AttributeName=studentId,AttributeType=S \
      AttributeName=examDate,AttributeType=S \
    --key-schema \
      AttributeName=studentId,KeyType=HASH \
      AttributeName=examDate,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST
  aws dynamodb wait table-exists --table-name wsc2026-student-score
fi
# Clear all items for grading prep
aws dynamodb scan --table-name wsc2026-student-score --query 'Items[*].[studentId.S,examDate.S]' --output text | \
while read -r sid ed; do
  [ -n "$sid" ] && aws dynamodb delete-item --table-name wsc2026-student-score \
    --key "{\"studentId\":{\"S\":\"$sid\"},\"examDate\":{\"S\":\"$ed\"}}" || true
done

# --- IAM Lambda Role ---
LAMBDA_ROLE="wsc2026-lambda-student-role"
if ! aws iam get-role --role-name "$LAMBDA_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$LAMBDA_ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }'
fi
aws iam attach-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

cat > "$WORK/lambda-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:HeadObject"],
      "Resource": ["arn:aws:s3:::${BUCKET}", "arn:aws:s3:::${BUCKET}/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:UpdateItem","dynamodb:DeleteItem","dynamodb:Scan","dynamodb:Query"],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/wsc2026-student-score"
    },
    {
      "Effect": "Allow",
      "Action": ["states:StartExecution"],
      "Resource": "arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:wsc2026-student-score-workflow"
    }
  ]
}
EOF
aws iam put-role-policy --role-name "$LAMBDA_ROLE" --policy-name student-lambda-inline \
  --policy-document "file://$WORK/lambda-policy.json"

# --- IAM Step Functions Role ---
SFN_ROLE="wsc2026-stepfunction-student-role"
if ! aws iam get-role --role-name "$SFN_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$SFN_ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }'
fi
cat > "$WORK/sfn-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["lambda:InvokeFunction"],
      "Resource": "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:wsc2026-student-score-function"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:HeadObject","s3:CopyObject"],
      "Resource": ["arn:aws:s3:::${BUCKET}", "arn:aws:s3:::${BUCKET}/*"]
    }
  ]
}
EOF
aws iam put-role-policy --role-name "$SFN_ROLE" --policy-name student-sfn-inline \
  --policy-document "file://$WORK/sfn-policy.json"

echo "Waiting for IAM role propagation..."
sleep 12

LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE" --query 'Role.Arn' --output text)
SFN_ROLE_ARN=$(aws iam get-role --role-name "$SFN_ROLE" --query 'Role.Arn' --output text)

# --- Score processing Lambda ---
cp "$BASE/lambda-function.py" "$WORK/index.py"
(cd "$WORK" && zip -q score.zip index.py)
if aws lambda get-function --function-name wsc2026-student-score-function >/dev/null 2>&1; then
  aws lambda update-function-code --function-name wsc2026-student-score-function --zip-file "fileb://$WORK/score.zip" >/dev/null
  aws lambda wait function-updated --function-name wsc2026-student-score-function
  aws lambda update-function-configuration --function-name wsc2026-student-score-function \
    --runtime python3.12 --handler index.handler --timeout 60 --memory-size 256 \
    --environment "Variables={S3_BUCKET=${BUCKET},DDB_TABLE=wsc2026-student-score}" \
    --role "$LAMBDA_ROLE_ARN" >/dev/null
else
  aws lambda create-function --function-name wsc2026-student-score-function \
    --runtime python3.12 --role "$LAMBDA_ROLE_ARN" --handler index.handler \
    --zip-file "fileb://$WORK/score.zip" --timeout 60 --memory-size 256 \
    --environment "Variables={S3_BUCKET=${BUCKET},DDB_TABLE=wsc2026-student-score}" >/dev/null
fi
aws lambda wait function-active --function-name wsc2026-student-score-function 2>/dev/null || true
SCORE_FN_ARN=$(aws lambda get-function --function-name wsc2026-student-score-function --query 'Configuration.FunctionArn' --output text)

# --- Trigger Lambda ---
cat > "$WORK/trigger.py" <<'PY'
import json
import os
import urllib.parse
import boto3

sfn = boto3.client("stepfunctions")
SM_ARN = os.environ["STATE_MACHINE_ARN"]

def handler(event, context):
    for rec in event.get("Records", []):
        key = urllib.parse.unquote_plus(rec["s3"]["object"]["key"])
        if not key.startswith("input/") or not key.endswith(".csv"):
            continue
        sfn.start_execution(
            stateMachineArn=SM_ARN,
            input=json.dumps({"key": key}),
        )
    return {"ok": True}
PY
(cd "$WORK" && zip -q trigger.zip trigger.py)
# Create SM first with placeholder then update - chicken/egg: create SM after both lambdas
# Temporarily create trigger without SM ARN env, update later

# --- Step Functions ---
cat > "$WORK/statemachine.json" <<EOF
{
  "Comment": "Student score workflow",
  "StartAt": "CheckS3File",
  "States": {
    "CheckS3File": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:headObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "Key.\$": "\$.key"
      },
      "ResultPath": "\$.head",
      "Next": "ProcessStudentData",
      "Catch": [{"ErrorEquals": ["States.ALL"], "Next": "FailState"}]
    },
    "ProcessStudentData": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${SCORE_FN_ARN}",
        "Payload": {
          "key.\$": "\$.key"
        }
      },
      "ResultSelector": {
        "statusCode.\$": "\$.Payload.statusCode",
        "processed.\$": "\$.Payload.processed",
        "errors.\$": "\$.Payload.errors",
        "key.\$": "\$.key"
      },
      "Retry": [{
        "ErrorEquals": ["States.ALL"],
        "IntervalSeconds": 2,
        "MaxAttempts": 3,
        "BackoffRate": 2.0
      }],
      "Next": "CheckResult"
    },
    "CheckResult": {
      "Type": "Choice",
      "Choices": [{
        "Variable": "\$.statusCode",
        "NumericEquals": 200,
        "Next": "MoveToProcessed"
      }],
      "Default": "MoveToError"
    },
    "MoveToProcessed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:copyObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "CopySource.\$": "States.Format('${BUCKET}/{}', \$.key)",
        "Key.\$": "States.Format('processed/{}', States.ArrayGetItem(States.StringSplit(\$.key, '/'), 1))"
      },
      "ResultPath": null,
      "Next": "DeleteInputProcessed"
    },
    "DeleteInputProcessed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:deleteObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "Key.\$": "\$.key"
      },
      "End": true
    },
    "MoveToError": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:copyObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "CopySource.\$": "States.Format('${BUCKET}/{}', \$.key)",
        "Key.\$": "States.Format('error/{}', States.ArrayGetItem(States.StringSplit(\$.key, '/'), 1))"
      },
      "ResultPath": null,
      "Next": "DeleteInputError"
    },
    "DeleteInputError": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:deleteObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "Key.\$": "\$.key"
      },
      "Next": "FailState"
    },
    "FailState": {
      "Type": "Fail",
      "Error": "WorkflowError",
      "Cause": "Student score workflow failed"
    }
  }
}
EOF

# Fix ProcessStudentData ResultSelector - key is lost from payload. Better approach:
cat > "$WORK/statemachine.json" <<EOF
{
  "Comment": "Student score workflow",
  "StartAt": "CheckS3File",
  "States": {
    "CheckS3File": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:headObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "Key.\$": "\$.key"
      },
      "ResultPath": "\$.head",
      "Next": "ProcessStudentData",
      "Catch": [{"ErrorEquals": ["States.ALL"], "Next": "FailState"}]
    },
    "ProcessStudentData": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${SCORE_FN_ARN}",
        "Payload": {
          "key.\$": "\$.key"
        }
      },
      "ResultPath": "\$.lambdaResult",
      "Retry": [{
        "ErrorEquals": ["States.ALL"],
        "IntervalSeconds": 2,
        "MaxAttempts": 3,
        "BackoffRate": 2.0
      }],
      "Next": "CheckResult"
    },
    "CheckResult": {
      "Type": "Choice",
      "Choices": [{
        "Variable": "\$.lambdaResult.Payload.statusCode",
        "NumericEquals": 200,
        "Next": "MoveToProcessed"
      }],
      "Default": "MoveToError"
    },
    "MoveToProcessed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:copyObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "CopySource.\$": "States.Format('${BUCKET}/{}', \$.key)",
        "Key.\$": "States.Format('processed/{}', States.ArrayGetItem(States.StringSplit(\$.key, '/'), 1))"
      },
      "ResultPath": null,
      "Next": "DeleteInputProcessed"
    },
    "DeleteInputProcessed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:deleteObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "Key.\$": "\$.key"
      },
      "End": true
    },
    "MoveToError": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:copyObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "CopySource.\$": "States.Format('${BUCKET}/{}', \$.key)",
        "Key.\$": "States.Format('error/{}', States.ArrayGetItem(States.StringSplit(\$.key, '/'), 1))"
      },
      "ResultPath": null,
      "Next": "DeleteInputError"
    },
    "DeleteInputError": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:deleteObject",
      "Parameters": {
        "Bucket": "${BUCKET}",
        "Key.\$": "\$.key"
      },
      "Next": "FailState"
    },
    "FailState": {
      "Type": "Fail",
      "Error": "WorkflowError",
      "Cause": "Student score workflow failed"
    }
  }
}
EOF

SM_ARN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text)
if [ -z "$SM_ARN" ] || [ "$SM_ARN" = "None" ]; then
  SM_ARN=$(aws stepfunctions create-state-machine \
    --name wsc2026-student-score-workflow \
    --definition "file://$WORK/statemachine.json" \
    --role-arn "$SFN_ROLE_ARN" \
    --type STANDARD \
    --query 'stateMachineArn' --output text)
else
  aws stepfunctions update-state-machine \
    --state-machine-arn "$SM_ARN" \
    --definition "file://$WORK/statemachine.json" \
    --role-arn "$SFN_ROLE_ARN" >/dev/null
fi
echo "StateMachine: $SM_ARN"

# Trigger lambda
if aws lambda get-function --function-name wsc2026-student-score-trigger >/dev/null 2>&1; then
  aws lambda update-function-code --function-name wsc2026-student-score-trigger --zip-file "fileb://$WORK/trigger.zip" >/dev/null
  aws lambda wait function-updated --function-name wsc2026-student-score-trigger
  aws lambda update-function-configuration --function-name wsc2026-student-score-trigger \
    --runtime python3.12 --handler trigger.handler --timeout 30 \
    --environment "Variables={STATE_MACHINE_ARN=${SM_ARN}}" \
    --role "$LAMBDA_ROLE_ARN" >/dev/null
else
  # rename trigger.py handler - zip contains trigger.py so handler is trigger.handler
  aws lambda create-function --function-name wsc2026-student-score-trigger \
    --runtime python3.12 --role "$LAMBDA_ROLE_ARN" --handler trigger.handler \
    --zip-file "fileb://$WORK/trigger.zip" --timeout 30 \
    --environment "Variables={STATE_MACHINE_ARN=${SM_ARN}}" >/dev/null
fi
TRIGGER_ARN=$(aws lambda get-function --function-name wsc2026-student-score-trigger --query 'Configuration.FunctionArn' --output text)

# S3 permission for trigger
aws lambda add-permission --function-name wsc2026-student-score-trigger \
  --statement-id s3invoke --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::${BUCKET}" 2>/dev/null || true

# S3 notification
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" \
  --notification-configuration "{
    \"LambdaFunctionConfigurations\": [{
      \"Id\": \"csv-upload-trigger\",
      \"LambdaFunctionArn\": \"${TRIGGER_ARN}\",
      \"Events\": [\"s3:ObjectCreated:*\"],
      \"Filter\": {
        \"Key\": {
          \"FilterRules\": [
            {\"Name\": \"prefix\", \"Value\": \"input/\"},
            {\"Name\": \"suffix\", \"Value\": \".csv\"}
          ]
        }
      }
    }]
  }"

# Ensure folders exist (empty markers may have been deleted)
: > "$WORK/empty"
aws s3api put-object --bucket "$BUCKET" --key "input/" --body "$WORK/empty" 2>/dev/null || true
aws s3api put-object --bucket "$BUCKET" --key "processed/" --body "$WORK/empty" 2>/dev/null || true
aws s3api put-object --bucket "$BUCKET" --key "error/" --body "$WORK/empty" 2>/dev/null || true

echo "=== Module1 infra ready. Uploading test.csv to trigger workflow ==="
# Clear previous results
aws s3 rm "s3://$BUCKET/processed/" --recursive 2>/dev/null || true
aws s3 rm "s3://$BUCKET/error/" --recursive 2>/dev/null || true
aws s3 rm "s3://$BUCKET/input/" --recursive 2>/dev/null || true

# Restore folder markers
aws s3api put-object --bucket "$BUCKET" --key "processed/" --body "$WORK/empty" >/dev/null
aws s3api put-object --bucket "$BUCKET" --key "error/" --body "$WORK/empty" >/dev/null

aws s3 cp "$BASE/test.csv" "s3://$BUCKET/input/test.csv"

echo "Waiting for workflow completion..."
for i in $(seq 1 30); do
  sleep 5
  STATUS=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" --max-results 1 --query 'executions[0].status' --output text 2>/dev/null || echo "NONE")
  echo "  attempt $i: $STATUS"
  if [ "$STATUS" = "SUCCEEDED" ] || [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "TIMED_OUT" ] || [ "$STATUS" = "ABORTED" ]; then
    break
  fi
done

echo "=== Module1 deploy done ==="
aws dynamodb get-item --table-name wsc2026-student-score \
  --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' \
  --query 'Item.[studentId.S,average.N,grade.S]' --output text
aws s3 ls "s3://$BUCKET/processed/"
aws s3 ls "s3://$BUCKET/error/"
