#!/bin/bash
# Deploy Module 4 - MSK Sensor Pipeline (ap-northeast-1)
set -euo pipefail

REGION="ap-northeast-1"
NUM="${NUM:-001}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="wsc2026-sensor-alert-bucket-${NUM}"
DDB_TABLE="wsc2026-sensor-data"
CLUSTER_NAME="wsc2026-msk-cluster"
BASE="/root/korean_skills_2026/day2/002/module4"
WORK="/tmp/m4-deploy"
LOG="/tmp/m4-deploy.log"

mkdir -p "$WORK"
exec > >(tee -a "$LOG") 2>&1

export AWS_DEFAULT_REGION="$REGION"
aws configure set region "$REGION"

echo "=== Module4 deploy account=$ACCOUNT_ID num=$NUM region=$REGION ==="

tag_name() {
  aws ec2 create-tags --resources "$1" --tags Key=Name,Value="$2" 2>/dev/null || true
}

get_or_create() {
  local desc="$1"
  shift
  echo ">>> $desc"
  "$@"
}

# ---------- S3 ----------
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi
chmod +x "$BASE/app"
aws s3 cp "$BASE/app" "s3://${BUCKET}/deploy/app"
aws s3 cp "s3://${BUCKET}/deploy/app" "$WORK/app-check" >/dev/null
chmod +x "$WORK/app-check"

# ---------- DynamoDB ----------
if ! aws dynamodb describe-table --table-name "$DDB_TABLE" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "$DDB_TABLE" \
    --attribute-definitions \
      AttributeName=sensorId,AttributeType=S \
      AttributeName=timestamp,AttributeType=S \
    --key-schema \
      AttributeName=sensorId,KeyType=HASH \
      AttributeName=timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST
  aws dynamodb wait table-exists --table-name "$DDB_TABLE"
fi

# ---------- SNS ----------
SNS_TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'wsc2026-sensor-alert')].TopicArn | [0]" --output text 2>/dev/null || true)
if [ -z "$SNS_TOPIC_ARN" ] || [ "$SNS_TOPIC_ARN" = "None" ]; then
  SNS_TOPIC_ARN=$(aws sns create-topic --name wsc2026-sensor-alert --query TopicArn --output text)
fi
echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN"

# ---------- VPC ----------
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=msk-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
  VPC_ID=$(aws ec2 create-vpc --cidr-block 192.168.0.0/16 --query Vpc.VpcId --output text)
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames Value=true
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support Value=true
  tag_name "$VPC_ID" msk-vpc
fi
echo "VPC_ID=$VPC_ID"

AZ_A="ap-northeast-1c"  # apne1-az1
AZ_D="ap-northeast-1a"  # apne1-az4

create_subnet() {
  local name="$1" cidr="$2" az="$3"
  local sid
  sid=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$name" \
    --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)
  if [ -z "$sid" ] || [ "$sid" = "None" ]; then
    sid=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$az" \
      --query Subnet.SubnetId --output text)
    tag_name "$sid" "$name"
  fi
  echo "$sid"
}

PUB_A=$(create_subnet msk-pub-a 192.168.0.0/24 "$AZ_A")
PUB_D=$(create_subnet msk-pub-d 192.168.1.0/24 "$AZ_D")
PRIV_A=$(create_subnet msk-priv-a 192.168.10.0/24 "$AZ_A")
PRIV_D=$(create_subnet msk-priv-d 192.168.11.0/24 "$AZ_D")
echo "Subnets: pub-a=$PUB_A pub-d=$PUB_D priv-a=$PRIV_A priv-d=$PRIV_D"

# IGW
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || true)
if [ -z "$IGW_ID" ] || [ "$IGW_ID" = "None" ]; then
  IGW_ID=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
  tag_name "$IGW_ID" msk-igw
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
fi

# Public RTB
PUB_RTB=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=msk-pub-rtb" \
  --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || true)
if [ -z "$PUB_RTB" ] || [ "$PUB_RTB" = "None" ]; then
  PUB_RTB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query RouteTable.RouteTableId --output text)
  tag_name "$PUB_RTB" msk-pub-rtb
fi
aws ec2 create-route --route-table-id "$PUB_RTB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" 2>/dev/null || true
for sn in "$PUB_A" "$PUB_D"; do
  aws ec2 associate-route-table --route-table-id "$PUB_RTB" --subnet-id "$sn" >/dev/null 2>&1 || true
done

# NAT
EIP_ALLOC=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=msk-nat-eip" \
  --query 'Addresses[0].AllocationId' --output text 2>/dev/null || true)
if [ -z "$EIP_ALLOC" ] || [ "$EIP_ALLOC" = "None" ]; then
  EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
  aws ec2 create-tags --resources "$EIP_ALLOC" --tags Key=Name,Value=msk-nat-eip
fi
NGW_ID=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
  --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null || true)
if [ -z "$NGW_ID" ] || [ "$NGW_ID" = "None" ]; then
  NGW_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUB_A" --allocation-id "$EIP_ALLOC" \
    --query NatGateway.NatGatewayId --output text)
  tag_name "$NGW_ID" msk-ngw
  aws ec2 wait nat-gateway-available --nat-gateway-ids "$NGW_ID"
fi

create_priv_rtb() {
  local name="$1" subnet="$2"
  local rtb
  rtb=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$name" \
    --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || true)
  if [ -z "$rtb" ] || [ "$rtb" = "None" ]; then
    rtb=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query RouteTable.RouteTableId --output text)
    tag_name "$rtb" "$name"
  fi
  aws ec2 create-route --route-table-id "$rtb" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NGW_ID" 2>/dev/null || true
  aws ec2 associate-route-table --route-table-id "$rtb" --subnet-id "$subnet" >/dev/null 2>&1 || true
  echo "$rtb"
}
PRIV_A_RTB=$(create_priv_rtb msk-priv-a-rtb "$PRIV_A")
PRIV_D_RTB=$(create_priv_rtb msk-priv-d-rtb "$PRIV_D")

# ---------- Security Groups ----------
get_sg() {
  aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$1" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true
}

MSK_SG=$(get_sg msk-sg)
if [ -z "$MSK_SG" ] || [ "$MSK_SG" = "None" ]; then
  MSK_SG=$(aws ec2 create-security-group --group-name msk-sg --description "MSK cluster SG" --vpc-id "$VPC_ID" \
    --query GroupId --output text)
  tag_name "$MSK_SG" msk-sg
fi

LAMBDA_SG=$(get_sg msk-lambda-sg)
if [ -z "$LAMBDA_SG" ] || [ "$LAMBDA_SG" = "None" ]; then
  LAMBDA_SG=$(aws ec2 create-security-group --group-name msk-lambda-sg --description "Lambda MSK SG" --vpc-id "$VPC_ID" \
    --query GroupId --output text)
  tag_name "$LAMBDA_SG" msk-lambda-sg
  aws ec2 authorize-security-group-egress --group-id "$LAMBDA_SG" --ip-permissions \
    IpProtocol=-1,IpRanges='[{CidrIp=0.0.0.0/0}]' 2>/dev/null || true
fi

EC2_SG=$(get_sg msk-ec2-sg)
if [ -z "$EC2_SG" ] || [ "$EC2_SG" = "None" ]; then
  EC2_SG=$(aws ec2 create-security-group --group-name msk-ec2-sg --description "EC2 producer SG" --vpc-id "$VPC_ID" \
    --query GroupId --output text)
  tag_name "$EC2_SG" msk-ec2-sg
  aws ec2 authorize-security-group-egress --group-id "$EC2_SG" --ip-permissions \
    IpProtocol=-1,IpRanges='[{CidrIp=0.0.0.0/0}]' 2>/dev/null || true
fi

# MSK broker + client port 9098
for src in "$LAMBDA_SG" "$EC2_SG" "$MSK_SG"; do
  aws ec2 authorize-security-group-ingress --group-id "$MSK_SG" --ip-permissions \
    IpProtocol=tcp,FromPort=9098,ToPort=9098,UserIdGroupPairs="[{GroupId=$src}]" 2>/dev/null || true
done
aws ec2 authorize-security-group-ingress --group-id "$MSK_SG" --ip-permissions \
  IpProtocol=tcp,FromPort=9098,ToPort=9098,UserIdGroupPairs="[{GroupId=$MSK_SG}]" 2>/dev/null || true

echo "SGs: msk=$MSK_SG lambda=$LAMBDA_SG ec2=$EC2_SG"

# ---------- IAM EC2 Role ----------
EC2_ROLE="wsc2026-msk-ec2-role"
if ! aws iam get-role --role-name "$EC2_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$EC2_ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }'
fi
aws iam attach-role-policy --role-name "$EC2_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

cat > "$WORK/ec2-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::${BUCKET}/deploy/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kafka-cluster:Connect",
        "kafka-cluster:DescribeTopic",
        "kafka-cluster:WriteData",
        "kafka-cluster:CreateTopic",
        "kafka-cluster:AlterTopic",
        "kafka-cluster:ReadData"
      ],
      "Resource": [
        "arn:aws:kafka:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}/*",
        "arn:aws:kafka:${REGION}:${ACCOUNT_ID}:topic/${CLUSTER_NAME}/*/*",
        "arn:aws:kafka:${REGION}:${ACCOUNT_ID}:group/${CLUSTER_NAME}/*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["kafka:DescribeCluster","kafka:DescribeClusterV2","kafka:GetBootstrapBrokers"],
      "Resource": "arn:aws:kafka:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}/*"
    }
  ]
}
EOF
aws iam put-role-policy --role-name "$EC2_ROLE" --policy-name msk-ec2-inline --policy-document "file://$WORK/ec2-policy.json"

if ! aws iam get-instance-profile --instance-profile-name "$EC2_ROLE" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$EC2_ROLE"
  aws iam add-role-to-instance-profile --instance-profile-name "$EC2_ROLE" --role-name "$EC2_ROLE"
fi

# ---------- IAM Lambda Role ----------
LAMBDA_ROLE="wsc2026-msk-lambda-role"
if ! aws iam get-role --role-name "$LAMBDA_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$LAMBDA_ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }'
fi
aws iam attach-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam attach-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole 2>/dev/null || true

cat > "$WORK/lambda-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:UpdateItem","dynamodb:Query","dynamodb:Scan"],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${DDB_TABLE}"
    },
    {
      "Effect": "Allow",
      "Action": ["sns:Publish"],
      "Resource": "${SNS_TOPIC_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject","s3:GetObject"],
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    },
    {
      "Effect": "Allow",
      "Action": ["kafka:DescribeCluster","kafka:DescribeClusterV2","kafka:GetBootstrapBrokers"],
      "Resource": "arn:aws:kafka:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kafka-cluster:Connect",
        "kafka-cluster:DescribeTopic",
        "kafka-cluster:ReadData",
        "kafka-cluster:WriteData",
        "kafka-cluster:DescribeGroup",
        "kafka-cluster:AlterGroup"
      ],
      "Resource": [
        "arn:aws:kafka:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}/*",
        "arn:aws:kafka:${REGION}:${ACCOUNT_ID}:topic/${CLUSTER_NAME}/*/*",
        "arn:aws:kafka:${REGION}:${ACCOUNT_ID}:group/${CLUSTER_NAME}/*/*"
      ]
    }
  ]
}
EOF
aws iam put-role-policy --role-name "$LAMBDA_ROLE" --policy-name msk-lambda-inline --policy-document "file://$WORK/lambda-policy.json"
LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE" --query Role.Arn --output text)
sleep 10

# ---------- MSK Cluster (start early) ----------
CLUSTER_ARN=$(aws kafka list-clusters --cluster-name-filter "$CLUSTER_NAME" \
  --query 'ClusterInfoList[0].ClusterArn' --output text 2>/dev/null || true)
if [ -z "$CLUSTER_ARN" ] || [ "$CLUSTER_ARN" = "None" ]; then
  echo "Creating MSK cluster (15-40 min)..."
  CLUSTER_ARN=$(aws kafka create-cluster \
    --cluster-name "$CLUSTER_NAME" \
    --kafka-version "3.6.0" \
    --number-of-broker-nodes 2 \
    --broker-node-group-info "{
      \"InstanceType\": \"kafka.t3.small\",
      \"ClientSubnets\": [\"$PRIV_A\", \"$PRIV_D\"],
      \"SecurityGroups\": [\"$MSK_SG\"],
      \"StorageInfo\": {\"EbsStorageInfo\": {\"VolumeSize\": 20}}
    }" \
    --encryption-info '{"EncryptionInTransit":{"ClientBroker":"TLS","InCluster":true}}' \
    --client-authentication '{"Sasl":{"Iam":{"Enabled":true}}}' \
    --query ClusterArn --output text)
fi
echo "CLUSTER_ARN=$CLUSTER_ARN"

# ---------- Lambda packages ----------
build_lambda_zip() {
  local name="$1" srcdir="$2" need_kafka="$3"
  local dir="$WORK/lambda-$name"
  rm -rf "$dir" "$WORK/${name}.zip"
  mkdir -p "$dir"
  cp "$srcdir/index.py" "$dir/"
  if [ "$need_kafka" = "yes" ]; then
    python3 -m pip install --quiet --break-system-packages --target "$dir" aws-msk-iam-sasl-signer-python kafka-python 2>/dev/null \
      || python3 -m pip install --quiet --target "$dir" aws-msk-iam-sasl-signer-python kafka-python
  fi
  (cd "$dir" && zip -qr9 "$WORK/${name}.zip" .)
}

build_lambda_zip sensor-consumer "$BASE/lambda/sensor-consumer" yes
build_lambda_zip alert-consumer "$BASE/lambda/alert-consumer" no

pick_runtime() {
  for rt in python3.14 python3.13 python3.12; do
    local probe="wsc2026-runtime-probe-$$"
    if aws lambda create-function \
      --function-name "$probe" \
      --runtime "$rt" \
      --role "$LAMBDA_ROLE_ARN" \
      --handler index.handler \
      --zip-file "fileb://${WORK}/alert-consumer.zip" \
      --timeout 10 \
      --query FunctionName --output text >/dev/null 2>&1; then
      aws lambda delete-function --function-name "$probe" 2>/dev/null || true
      echo "$rt"
      return 0
    fi
  done
  echo "python3.13"
}

LAMBDA_RUNTIME="${LAMBDA_RUNTIME:-}"
if [ -z "$LAMBDA_RUNTIME" ]; then
  LAMBDA_RUNTIME=$(pick_runtime)
fi
echo "LAMBDA_RUNTIME=$LAMBDA_RUNTIME"

deploy_lambda() {
  local fn="$1" zip="$2" env_vars="$3"
  if aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
    aws lambda update-function-code --function-name "$fn" --zip-file "fileb://${WORK}/${zip}.zip" >/dev/null
    sleep 5
    aws lambda update-function-configuration --function-name "$fn" \
      --runtime "$LAMBDA_RUNTIME" \
      --handler index.handler \
      --timeout 60 \
      --memory-size 256 \
      --vpc-config "SubnetIds=$PRIV_A,$PRIV_D,SecurityGroupIds=$LAMBDA_SG" \
      --environment "Variables={$env_vars}" >/dev/null
  else
    aws lambda create-function \
      --function-name "$fn" \
      --runtime "$LAMBDA_RUNTIME" \
      --role "$LAMBDA_ROLE_ARN" \
      --handler index.handler \
      --zip-file "fileb://${WORK}/${zip}.zip" \
      --timeout 60 \
      --memory-size 256 \
      --vpc-config "SubnetIds=$PRIV_A,$PRIV_D,SecurityGroupIds=$LAMBDA_SG" \
      --environment "Variables={$env_vars}" >/dev/null
  fi
  aws lambda wait function-active-v2 --function-name "$fn" 2>/dev/null || sleep 15
}

# Wait for MSK ACTIVE before lambda env with bootstrap
echo "Waiting for MSK cluster ACTIVE..."
for i in $(seq 1 120); do
  STATE=$(aws kafka describe-cluster --cluster-arn "$CLUSTER_ARN" --query 'ClusterInfo.State' --output text)
  echo "  MSK state=$STATE (attempt $i)"
  [ "$STATE" = "ACTIVE" ] && break
  sleep 30
done
STATE=$(aws kafka describe-cluster --cluster-arn "$CLUSTER_ARN" --query 'ClusterInfo.State' --output text)
if [ "$STATE" != "ACTIVE" ]; then
  echo "ERROR: MSK not ACTIVE yet: $STATE"
  exit 1
fi

BOOTSTRAP=$(aws kafka get-bootstrap-brokers --cluster-arn "$CLUSTER_ARN" --query BootstrapBrokerStringSaslIam --output text)
echo "BOOTSTRAP=$BOOTSTRAP"

deploy_lambda wsc2026-sensor-consumer sensor-consumer \
  "DDB_TABLE=${DDB_TABLE},ALERT_TOPIC=wsc2026-sensor-alert,BOOTSTRAP_SERVER=${BOOTSTRAP}"
deploy_lambda wsc2026-sensor-alert-consumer alert-consumer \
  "SNS_TOPIC_ARN=${SNS_TOPIC_ARN},S3_BUCKET=${BUCKET}"

# ---------- Event Source Mappings ----------
create_esm() {
  local fn="$1" topic="$2"
  local existing
  existing=$(aws lambda list-event-source-mappings --function-name "$fn" \
    --query "EventSourceMappings[?Topics[0]=='${topic}'].UUID | [0]" --output text 2>/dev/null || true)
  if [ -n "$existing" ] && [ "$existing" != "None" ]; then
    aws lambda update-event-source-mapping --uuid "$existing" --enabled >/dev/null
    return
  fi
  aws lambda create-event-source-mapping \
    --function-name "$fn" \
    --event-source-arn "$CLUSTER_ARN" \
    --topics "$topic" \
    --starting-position LATEST \
    --batch-size 10 \
    --enabled >/dev/null
}

create_esm wsc2026-sensor-consumer wsc2026-sensor-raw
create_esm wsc2026-sensor-alert-consumer wsc2026-sensor-alert

# ---------- EC2 Producer + Topic creation ----------
AMI_ID=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)

USER_DATA=$(cat <<'USERDATA'
#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1
BUCKET="__BUCKET__"
BOOTSTRAP="__BOOTSTRAP__"
REGION="__REGION__"

dnf install -y java-17-amazon-corretto-headless aws-cli
mkdir -p /opt/app /opt/kafka
aws s3 cp "s3://${BUCKET}/deploy/app" /opt/app/app --region "${REGION}"
chmod +x /opt/app/app

curl -fsSL -o /tmp/kafka.tgz https://archive.apache.org/dist/kafka/3.6.0/kafka_2.13-3.6.0.tgz
tar -xzf /tmp/kafka.tgz -C /opt/kafka --strip-components=1
curl -fsSL -o /opt/kafka/libs/aws-msk-iam-auth.jar \
  https://github.com/aws/aws-msk-iam-auth/releases/download/v2.2.0/aws-msk-iam-auth-2.2.0-all.jar

cat > /opt/kafka/client.properties <<EOF
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOF

for topic_part in "wsc2026-sensor-raw:3" "wsc2026-sensor-alert:1"; do
  t="${topic_part%%:*}"
  p="${topic_part##*:}"
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server "${BOOTSTRAP}" \
    --command-config /opt/kafka/client.properties \
    --create --if-not-exists --topic "$t" --partitions "$p" --replication-factor 2 || true
done

cat > /etc/systemd/system/sensor-producer.service <<EOF
[Unit]
Description=WSC2026 Sensor Producer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=BOOTSTRAP_SERVERS=${BOOTSTRAP}
Environment=TOPIC_RAW=wsc2026-sensor-raw
ExecStart=/opt/app/app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sensor-producer
systemctl start sensor-producer
USERDATA
)
USER_DATA="${USER_DATA//__BUCKET__/$BUCKET}"
USER_DATA="${USER_DATA//__BOOTSTRAP__/$BOOTSTRAP}"
USER_DATA="${USER_DATA//__REGION__/$REGION}"
B64_USER=$(echo "$USER_DATA" | base64 -w0)

INSTANCE_ID=$(aws ec2 describe-instances --filters \
  "Name=tag:Name,Values=wsc2026-sensor-producer" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.small \
    --subnet-id "$PRIV_A" \
    --security-group-ids "$EC2_SG" \
    --iam-instance-profile Name="$EC2_ROLE" \
    --user-data "$B64_USER" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=wsc2026-sensor-producer}]" \
    --metadata-options HttpTokens=required \
    --query Instances[0].InstanceId --output text)
else
  aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null 2>&1 || true
fi
echo "INSTANCE_ID=$INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

echo "Waiting 120s for producer + data pipeline..."
sleep 120

echo "=== Verification ==="
aws kafka describe-cluster --cluster-arn "$CLUSTER_ARN" \
  --query 'ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]' \
  --output text
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  aws lambda get-function --function-name "$fn" --query 'Configuration.[FunctionName,Runtime,State]' --output text
  aws lambda list-event-source-mappings --function-name "$fn" --query 'EventSourceMappings[0].[State,Topics[0]]' --output text
done
aws dynamodb scan --table-name "$DDB_TABLE" --max-items 3 \
  --query 'Items[*].{sensorId:sensorId.S,temperature:temperature.S,status:status.S,timestamp:timestamp.S}' --output json
echo "Deploy log: $LOG"
echo "DONE cluster=$CLUSTER_ARN bootstrap=$BOOTSTRAP"
