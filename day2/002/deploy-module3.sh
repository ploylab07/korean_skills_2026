#!/bin/bash
# Deploy Module3 Cloud Event Handling - eu-west-1
set -euo pipefail

REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BASE="/root/korean_skills_2026/day2/002/module3"
WORK="/tmp/m3-deploy"
CONFIG_BUCKET="wsc2026-event-config-${ACCOUNT_ID}"
TRAIL_BUCKET="wsc2026-event-trail-${ACCOUNT_ID}"

mkdir -p "$WORK"
export AWS_DEFAULT_REGION="$REGION"
aws configure set region "$REGION"

echo "=== Module3 deploy: account=$ACCOUNT_ID region=$REGION ==="

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
get_vpc_id() {
  aws ec2 describe-vpcs --filters "Name=tag:Name,Values=event-vpc" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null
}

VPC_ID=$(get_vpc_id)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
  VPC_ID=$(aws ec2 create-vpc --cidr-block 172.16.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=event-vpc}]' \
    --query 'Vpc.VpcId' --output text)
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
  echo "Created VPC: $VPC_ID"
else
  echo "VPC exists: $VPC_ID"
fi

get_subnet_id() {
  local name=$1
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$name" \
    --query 'Subnets[0].SubnetId' --output text 2>/dev/null
}

SUBNET_A=$(get_subnet_id event-pub-a)
if [ -z "$SUBNET_A" ] || [ "$SUBNET_A" = "None" ]; then
  SUBNET_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 172.16.0.0/24 \
    --availability-zone "${REGION}a" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=event-pub-a}]' \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_A" --map-public-ip-on-launch
fi

SUBNET_B=$(get_subnet_id event-pub-b)
if [ -z "$SUBNET_B" ] || [ "$SUBNET_B" = "None" ]; then
  SUBNET_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 172.16.1.0/24 \
    --availability-zone "${REGION}b" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=event-pub-b}]' \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_B" --map-public-ip-on-launch
fi

IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
if [ -z "$IGW_ID" ] || [ "$IGW_ID" = "None" ]; then
  IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=event-igw}]' \
    --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
fi

RTB_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=event-pub-rtb" \
  --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
if [ -z "$RTB_ID" ] || [ "$RTB_ID" = "None" ]; then
  RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=event-pub-rtb}]' \
    --query 'RouteTable.RouteTableId' --output text)
fi
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" 2>/dev/null || true
for sid in "$SUBNET_A" "$SUBNET_B"; do
  aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$sid" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# IAM roles
# ---------------------------------------------------------------------------
EC2_ROLE="wsc2026-event-ec2-role"
if ! aws iam get-role --role-name "$EC2_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$EC2_ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }'
fi
aws iam attach-role-policy --role-name "$EC2_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

if ! aws iam get-instance-profile --instance-profile-name "$EC2_ROLE" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$EC2_ROLE"
  aws iam add-role-to-instance-profile --instance-profile-name "$EC2_ROLE" --role-name "$EC2_ROLE"
  sleep 5
fi

LAMBDA_ROLE="wsc2026-event-lambda-role"
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
    {"Effect": "Allow", "Action": ["ec2:*"], "Resource": "*"},
    {"Effect": "Allow", "Action": ["sns:Publish"], "Resource": "*"},
    {"Effect": "Allow", "Action": ["iam:GetInstanceProfile", "iam:ListInstanceProfiles", "iam:PassRole"], "Resource": "*"},
    {"Effect": "Allow", "Action": ["config:Describe*", "config:Get*", "config:List*"], "Resource": "*"}
  ]
}
EOF
aws iam put-role-policy --role-name "$LAMBDA_ROLE" --policy-name event-lambda-inline \
  --policy-document "file://$WORK/lambda-policy.json"

CONFIG_ROLE="wsc2026-event-config-role"
if ! aws iam get-role --role-name "$CONFIG_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$CONFIG_ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"config.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }'
fi
cat > "$WORK/config-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketAcl", "s3:ListBucket", "s3:PutObject"],
      "Resource": ["arn:aws:s3:::${CONFIG_BUCKET}", "arn:aws:s3:::${CONFIG_BUCKET}/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["config:Put*"],
      "Resource": "*"
    }
  ]
}
EOF
aws iam put-role-policy --role-name "$CONFIG_ROLE" --policy-name config-s3-inline \
  --policy-document "file://$WORK/config-policy.json"
aws iam attach-role-policy --role-name "$CONFIG_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWS_ConfigRole 2>/dev/null || true

echo "Waiting for IAM propagation..."
sleep 12

LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE" --query 'Role.Arn' --output text)
CONFIG_ROLE_ARN=$(aws iam get-role --role-name "$CONFIG_ROLE" --query 'Role.Arn' --output text)

# ---------------------------------------------------------------------------
# S3 buckets (Config + CloudTrail)
# ---------------------------------------------------------------------------
create_bucket() {
  local b=$1
  if aws s3api head-bucket --bucket "$b" 2>/dev/null; then
    return 0
  fi
  aws s3api create-bucket --bucket "$b" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
}

create_bucket "$CONFIG_BUCKET"
create_bucket "$TRAIL_BUCKET"

cat > "$WORK/trail-bucket-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AWSCloudTrailAclCheck",
    "Effect": "Allow",
    "Principal": {"Service": "cloudtrail.amazonaws.com"},
    "Action": "s3:GetBucketAcl",
    "Resource": "arn:aws:s3:::${TRAIL_BUCKET}"
  }, {
    "Sid": "AWSCloudTrailWrite",
    "Effect": "Allow",
    "Principal": {"Service": "cloudtrail.amazonaws.com"},
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::${TRAIL_BUCKET}/AWSLogs/${ACCOUNT_ID}/*",
    "Condition": {"StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}}
  }]
}
EOF
aws s3api put-bucket-policy --bucket "$TRAIL_BUCKET" --policy "file://$WORK/trail-bucket-policy.json"

# ---------------------------------------------------------------------------
# AWS Config
# ---------------------------------------------------------------------------
RECORDER=$(aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[0].name' --output text 2>/dev/null || echo "None")
if [ -z "$RECORDER" ] || [ "$RECORDER" = "None" ]; then
  aws configservice put-configuration-recorder --configuration-recorder "{
    \"name\": \"default\",
    \"roleARN\": \"${CONFIG_ROLE_ARN}\",
    \"recordingGroup\": {
      \"allSupported\": true,
      \"includeGlobalResourceTypes\": true
    }
  }"
fi

CHANNEL=$(aws configservice describe-delivery-channels --query 'DeliveryChannels[0].name' --output text 2>/dev/null || echo "None")
if [ -z "$CHANNEL" ] || [ "$CHANNEL" = "None" ]; then
  aws configservice put-delivery-channel --delivery-channel "{
    \"name\": \"default\",
    \"s3BucketName\": \"${CONFIG_BUCKET}\"
  }"
fi

REC_STATUS=$(aws configservice describe-configuration-recorder-status \
  --query 'ConfigurationRecordersStatus[0].recording' --output text 2>/dev/null || echo "false")
if [ "$REC_STATUS" != "true" ]; then
  aws configservice start-configuration-recorder --configuration-recorder-name default
fi

# Config rules
put_config_rule() {
  local name=$1
  local doc=$2
  if aws configservice describe-config-rules --config-rule-names "$name" >/dev/null 2>&1; then
    aws configservice put-config-rule --config-rule "$doc" >/dev/null
  else
    aws configservice put-config-rule --config-rule "$doc" >/dev/null
  fi
}

put_config_rule wsc2026-sg-ssh-rule '{
  "ConfigRuleName": "wsc2026-sg-ssh-rule",
  "Description": "Detect unrestricted SSH access",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "INCOMING_SSH_DISABLED"
  },
  "Scope": {
    "ComplianceResourceTypes": ["AWS::EC2::SecurityGroup"]
  }
}'

put_config_rule wsc2026-required-tags-rule '{
  "ConfigRuleName": "wsc2026-required-tags-rule",
  "Description": "Require Name and Environment tags on EC2",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "REQUIRED_TAGS"
  },
  "InputParameters": "{\"tag1Key\":\"Name\",\"tag2Key\":\"Environment\"}",
  "Scope": {
    "ComplianceResourceTypes": ["AWS::EC2::Instance"]
  }
}'

# ---------------------------------------------------------------------------
# CloudTrail (management events for SG EventBridge)
# ---------------------------------------------------------------------------
TRAIL_ARN=$(aws cloudtrail describe-trails --trail-name-list wsc2026-event-trail \
  --query 'trailList[0].TrailARN' --output text 2>/dev/null || echo "None")
if [ -z "$TRAIL_ARN" ] || [ "$TRAIL_ARN" = "None" ]; then
  aws cloudtrail create-trail \
    --name wsc2026-event-trail \
    --s3-bucket-name "$TRAIL_BUCKET" \
    --is-multi-region-trail \
    --include-global-service-events \
    --enable-log-file-validation >/dev/null
fi
aws cloudtrail start-logging --name wsc2026-event-trail 2>/dev/null || true

# ---------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=wsc2026-event-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group --group-name wsc2026-event-sg \
    --description "WSC2026 event handling SG" --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=wsc2026-event-sg}]' \
    --query 'GroupId' --output text)
fi
# Ensure no inbound rules
INBOUND=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions | length(@)' --output text)
if [ "$INBOUND" != "0" ] && [ "$INBOUND" != "None" ]; then
  PERMS=$(aws ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissions' --output json)
  if [ "$PERMS" != "[]" ] && [ "$PERMS" != "null" ]; then
    aws ec2 revoke-security-group-ingress --group-id "$SG_ID" --ip-permissions "$PERMS" 2>/dev/null || true
  fi
fi
aws ec2 authorize-security-group-egress --group-id "$SG_ID" --protocol -1 --cidr 0.0.0.0/0 2>/dev/null || true

# ---------------------------------------------------------------------------
# EC2 instance
# ---------------------------------------------------------------------------
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text)

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=wsc2026-event-ec2" "Name=instance-state-name,Values=running,stopped,pending,stopping" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type t3.micro \
    --subnet-id "$SUBNET_A" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile Name="$EC2_ROLE" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=wsc2026-event-ec2},{Key=Environment,Value=production}]' \
    --query 'Instances[0].InstanceId' --output text)
  echo "Launched EC2: $INSTANCE_ID"
else
  aws ec2 create-tags --resources "$INSTANCE_ID" \
    --tags Key=Name,Value=wsc2026-event-ec2 Key=Environment,Value=production
  STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text)
  if [ "$STATE" = "stopped" ]; then
    aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null
  fi
  echo "EC2 exists: $INSTANCE_ID ($STATE)"
fi

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" 2>/dev/null || true

# ---------------------------------------------------------------------------
# SNS
# ---------------------------------------------------------------------------
SNS_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:wsc2026-event-alert"
if ! aws sns get-topic-attributes --topic-arn "$SNS_ARN" >/dev/null 2>&1; then
  SNS_ARN=$(aws sns create-topic --name wsc2026-event-alert --query 'TopicArn' --output text)
fi

# ---------------------------------------------------------------------------
# Lambda functions
# ---------------------------------------------------------------------------
cp "$BASE/lambda-function.py" "$WORK/index.py"
(cd "$WORK" && zip -q lambda.zip index.py)

deploy_lambda() {
  local fn=$1
  local handler=$2
  shift 2
  local env_vars="$1"

  if aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
    aws lambda update-function-code --function-name "$fn" --zip-file "fileb://$WORK/lambda.zip" >/dev/null
    aws lambda wait function-updated --function-name "$fn"
    aws lambda update-function-configuration --function-name "$fn" \
      --runtime python3.12 --handler "$handler" --timeout 120 --memory-size 256 \
      --environment "Variables={${env_vars}}" --role "$LAMBDA_ROLE_ARN" >/dev/null
  else
    aws lambda create-function --function-name "$fn" \
      --runtime python3.12 --role "$LAMBDA_ROLE_ARN" --handler "$handler" \
      --zip-file "fileb://$WORK/lambda.zip" --timeout 120 --memory-size 256 \
      --environment "Variables={${env_vars}}" >/dev/null
  fi
  aws lambda wait function-active --function-name "$fn" 2>/dev/null || true
}

SNS_VAR="SNS_TOPIC_ARN=${SNS_ARN}"
deploy_lambda wsc2026-sg-remediation index.sg_remediation_handler "${SNS_VAR},SECURITY_GROUP_ID=${SG_ID}"
deploy_lambda wsc2026-ec2-stop-remediation index.ec2_stop_remediation_handler "${SNS_VAR},INSTANCE_ID=${INSTANCE_ID}"
deploy_lambda wsc2026-ec2-terminate-alert index.ec2_terminate_handler "${SNS_VAR}"
deploy_lambda wsc2026-tag-alert index.tag_alert_handler "${SNS_VAR}"

SG_FN_ARN=$(aws lambda get-function --function-name wsc2026-sg-remediation --query 'Configuration.FunctionArn' --output text)
STOP_FN_ARN=$(aws lambda get-function --function-name wsc2026-ec2-stop-remediation --query 'Configuration.FunctionArn' --output text)
TERM_FN_ARN=$(aws lambda get-function --function-name wsc2026-ec2-terminate-alert --query 'Configuration.FunctionArn' --output text)

# ---------------------------------------------------------------------------
# EventBridge rules
# ---------------------------------------------------------------------------
put_rule() {
  local rule=$1
  local pattern=$2
  aws events put-rule --name "$rule" --state ENABLED --event-pattern "$pattern" >/dev/null
}

put_rule wsc2026-ec2-stop-rule '{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance State-change Notification"],
  "detail": {"state": ["stopped", "stopping"]}
}'

put_rule wsc2026-ec2-terminate-rule '{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance State-change Notification"],
  "detail": {"state": ["terminated"]}
}'

put_rule wsc2026-sg-change-rule '{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["AuthorizeSecurityGroupIngress"]
  }
}'

add_target() {
  local rule=$1
  local arn=$2
  aws events put-targets --rule "$rule" --targets "Id=1,Arn=${arn}" >/dev/null
}

add_target wsc2026-ec2-stop-rule "$STOP_FN_ARN"
add_target wsc2026-ec2-terminate-rule "$TERM_FN_ARN"
add_target wsc2026-sg-change-rule "$SG_FN_ARN"

add_lambda_permission() {
  local fn=$1
  local rule=$2
  aws lambda add-permission --function-name "$fn" \
    --statement-id "${rule}-invoke" --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${REGION}:${ACCOUNT_ID}:rule/${rule}" 2>/dev/null || true
}

add_lambda_permission wsc2026-ec2-stop-remediation wsc2026-ec2-stop-rule
add_lambda_permission wsc2026-ec2-terminate-alert wsc2026-ec2-terminate-rule
add_lambda_permission wsc2026-sg-remediation wsc2026-sg-change-rule

# ---------------------------------------------------------------------------
# Summary / verification
# ---------------------------------------------------------------------------
echo ""
echo "=== Module3 deploy complete ==="
echo "VPC:           $VPC_ID"
echo "Subnet A:      $SUBNET_A"
echo "Instance ID:   $INSTANCE_ID"
echo "Security Group:$SG_ID"
echo "SNS Topic:     $SNS_ARN"
echo ""
echo "--- Lambdas ---"
for fn in wsc2026-ec2-stop-remediation wsc2026-ec2-terminate-alert wsc2026-sg-remediation wsc2026-tag-alert; do
  aws lambda get-function --function-name "$fn" --query 'Configuration.[FunctionName,Runtime,Handler]' --output text
done
echo ""
echo "--- EventBridge ---"
for rule in wsc2026-ec2-stop-rule wsc2026-ec2-terminate-rule wsc2026-sg-change-rule; do
  echo "$rule -> $(aws events list-targets-by-rule --rule "$rule" --query 'Targets[0].Arn' --output text)"
done
echo ""
echo "--- Config Rules ---"
aws configservice describe-config-rules --config-rule-names wsc2026-sg-ssh-rule wsc2026-required-tags-rule \
  --query 'ConfigRules[*].[ConfigRuleName,ConfigRuleState]' --output text
echo ""
echo "Run mark2-3.sh to verify remediation (stops EC2 + adds SSH, waits 30s)."
