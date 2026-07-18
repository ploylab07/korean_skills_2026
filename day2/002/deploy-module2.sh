#!/bin/bash
# Deploy Module2 Real-time Analytics - ap-northeast-2
set -euo pipefail

REGION="ap-northeast-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BASE="/root/korean_skills_2026/day2/002/module2"
WORK="/tmp/m2-deploy"
mkdir -p "$WORK"

export AWS_DEFAULT_REGION="$REGION"
aws configure set region "$REGION"

echo "=== Module2 deploy: account=$ACCOUNT_ID region=$REGION ==="

get_subnet_id() {
  local name="$1"
  aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=$name" "Name=state,Values=available" \
    --query 'Subnets[0].SubnetId' --output text 2>/dev/null | grep -v '^None$' || true
}

tag_resource() {
  local id="$1" name="$2"
  aws ec2 create-tags --resources "$id" --tags "Key=Name,Value=$name" 2>/dev/null || true
}

# --- VPC ---
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=analytics-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  VPC_ID=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 --query 'Vpc.VpcId' --output text)
  tag_resource "$VPC_ID" "analytics-vpc"
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
  echo "Created VPC $VPC_ID"
else
  echo "VPC exists: $VPC_ID"
fi

AZS=($(aws ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName' --output text))
AZ_A="${AZS[0]}"
AZ_B="${AZS[1]}"

create_subnet() {
  local name="$1" cidr="$2" az="$3"
  local sid
  sid=$(get_subnet_id "$name")
  if [ -z "$sid" ]; then
    sid=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$az" --query 'Subnet.SubnetId' --output text)
    tag_resource "$sid" "$name"
    echo "Created subnet $name ($sid)" >&2
  else
    echo "Subnet exists: $name ($sid)" >&2
  fi
  echo "$sid"
}

PUB_A=$(create_subnet "analytics-pub-a" "10.20.0.0/24" "$AZ_A")
PUB_B=$(create_subnet "analytics-pub-b" "10.20.1.0/24" "$AZ_B")
PRIV_A=$(create_subnet "analytics-priv-a" "10.20.100.0/24" "$AZ_A")
PRIV_B=$(create_subnet "analytics-priv-b" "10.20.101.0/24" "$AZ_B")

# --- IGW ---
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=analytics-igw" "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "None")
if [ "$IGW_ID" = "None" ] || [ -z "$IGW_ID" ]; then
  IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
  tag_resource "$IGW_ID" "analytics-igw"
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
  echo "Created IGW $IGW_ID"
else
  echo "IGW exists: $IGW_ID"
fi

# --- Public RTB ---
PUB_RTB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=analytics-pub-rtb" "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "None")
if [ "$PUB_RTB" = "None" ] || [ -z "$PUB_RTB" ]; then
  PUB_RTB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)
  tag_resource "$PUB_RTB" "analytics-pub-rtb"
  echo "Created pub RTB $PUB_RTB"
fi
aws ec2 create-route --route-table-id "$PUB_RTB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" 2>/dev/null || true
for sid in "$PUB_A" "$PUB_B"; do
  assoc=$(aws ec2 describe-route-tables --route-table-ids "$PUB_RTB" --query "RouteTables[0].Associations[?SubnetId=='$sid'].RouteTableAssociationId" --output text 2>/dev/null || true)
  if [ -z "$assoc" ] || [ "$assoc" = "None" ]; then
    aws ec2 associate-route-table --route-table-id "$PUB_RTB" --subnet-id "$sid" >/dev/null 2>&1 || true
  fi
done

# --- NAT in pub-a (gateway preferred; EC2 NAT instance if EIP quota exceeded) ---
NAT_TARGET=""
NAT_TARGET_KIND=""

NGW_ID=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=analytics-ngw" "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null || echo "None")
if [ "$NGW_ID" != "None" ] && [ -n "$NGW_ID" ]; then
  NAT_TARGET="$NGW_ID"
  NAT_TARGET_KIND="ngw"
  echo "NAT gateway exists: $NGW_ID"
else
  NAT_INST=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=analytics-ngw" "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "None")
  if [ "$NAT_INST" != "None" ] && [ -n "$NAT_INST" ]; then
    NAT_TARGET="$NAT_INST"
    NAT_TARGET_KIND="instance"
    echo "NAT instance exists: $NAT_INST"
  else
    EIP_ALLOC=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=analytics-ngw-eip" --query 'Addresses[0].AllocationId' --output text 2>/dev/null || echo "None")
    if [ "$EIP_ALLOC" = "None" ] || [ -z "$EIP_ALLOC" ]; then
      EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text 2>/dev/null || echo "FAILED")
      if [ "$EIP_ALLOC" != "FAILED" ]; then
        aws ec2 create-tags --resources "$EIP_ALLOC" --tags "Key=Name,Value=analytics-ngw-eip"
      fi
    fi
    if [ "$EIP_ALLOC" != "FAILED" ] && [ -n "$EIP_ALLOC" ] && [ "$EIP_ALLOC" != "None" ]; then
      NGW_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUB_A" --allocation-id "$EIP_ALLOC" --query 'NatGateway.NatGatewayId' --output text)
      tag_resource "$NGW_ID" "analytics-ngw"
      echo "Waiting for NAT gateway..."
      aws ec2 wait nat-gateway-available --nat-gateway-ids "$NGW_ID"
      NAT_TARGET="$NGW_ID"
      NAT_TARGET_KIND="ngw"
      echo "NAT gateway ready: $NGW_ID"
    else
      echo "EIP quota exceeded; creating NAT instance analytics-ngw in pub-a"
      NAT_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=analytics-ngw-sg" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
      if [ "$NAT_SG" = "None" ] || [ -z "$NAT_SG" ]; then
        NAT_SG=$(aws ec2 create-security-group --group-name analytics-ngw-sg --description "NAT instance SG" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
        tag_resource "$NAT_SG" "analytics-ngw-sg"
        aws ec2 authorize-security-group-ingress --group-id "$NAT_SG" --protocol -1 --cidr 10.20.0.0/16 2>/dev/null || true
        aws ec2 authorize-security-group-egress --group-id "$NAT_SG" --protocol -1 --cidr 0.0.0.0/0 2>/dev/null || true
      fi
      NAT_AMI=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query 'Parameters[0].Value' --output text)
      cat > "$WORK/nat-user-data.sh" <<'NATUD'
#!/bin/bash
set -ex
sysctl -w net.ipv4.ip_forward=1
grep -q 'net.ipv4.ip_forward = 1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
dnf install -y iptables-services
iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
service iptables save
systemctl enable iptables
systemctl start iptables
NATUD
      NAT_INST=$(aws ec2 run-instances \
        --image-id "$NAT_AMI" \
        --instance-type t3.nano \
        --subnet-id "$PUB_A" \
        --security-group-ids "$NAT_SG" \
        --associate-public-ip-address \
        --user-data "file://$WORK/nat-user-data.sh" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=analytics-ngw}]" \
        --query 'Instances[0].InstanceId' --output text)
      aws ec2 modify-instance-attribute --instance-id "$NAT_INST" --no-source-dest-check
      aws ec2 wait instance-running --instance-ids "$NAT_INST"
      sleep 30
      NAT_TARGET="$NAT_INST"
      NAT_TARGET_KIND="instance"
      echo "NAT instance ready: $NAT_INST"
    fi
  fi
fi

create_priv_rtb() {
  local name="$1" subnet_id="$2"
  local rtb
  rtb=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$name" "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "None")
  if [ "$rtb" = "None" ] || [ -z "$rtb" ]; then
    rtb=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)
    tag_resource "$rtb" "$name"
  fi
  if [ "$NAT_TARGET_KIND" = "ngw" ]; then
    aws ec2 create-route --route-table-id "$rtb" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_TARGET" >/dev/null 2>&1 || true
  else
    aws ec2 create-route --route-table-id "$rtb" --destination-cidr-block 0.0.0.0/0 --instance-id "$NAT_TARGET" >/dev/null 2>&1 || true
  fi
  assoc=$(aws ec2 describe-route-tables --route-table-ids "$rtb" --query "RouteTables[0].Associations[?SubnetId=='$subnet_id'].RouteTableAssociationId" --output text 2>/dev/null || true)
  if [ -z "$assoc" ] || [ "$assoc" = "None" ]; then
    aws ec2 associate-route-table --route-table-id "$rtb" --subnet-id "$subnet_id" >/dev/null 2>&1 || true
  fi
  echo "$rtb"
}

PRIV_A_RTB=$(create_priv_rtb "analytics-priv-a-rtb" "$PRIV_A")
PRIV_B_RTB=$(create_priv_rtb "analytics-priv-b-rtb" "$PRIV_B")
echo "Private RTBs: $PRIV_A_RTB, $PRIV_B_RTB"

# --- Kinesis ---
if ! aws kinesis describe-stream-summary --stream-name wsc2026-order-stream >/dev/null 2>&1; then
  aws kinesis create-stream --stream-name wsc2026-order-stream \
    --stream-mode-details StreamMode=ON_DEMAND
  echo "Created Kinesis stream"
fi
echo "Waiting for Kinesis ACTIVE..."
for i in $(seq 1 30); do
  STATUS=$(aws kinesis describe-stream-summary --stream-name wsc2026-order-stream --query 'StreamDescriptionSummary.StreamStatus' --output text)
  [ "$STATUS" = "ACTIVE" ] && break
  sleep 5
done
STREAM_ARN=$(aws kinesis describe-stream-summary --stream-name wsc2026-order-stream --query 'StreamDescriptionSummary.StreamARN' --output text)
echo "Kinesis: $STREAM_ARN ($STATUS)"

# --- IAM EC2 Role ---
EC2_ROLE="wsc2026-alaytics-ec2-role"
if ! aws iam get-role --role-name "$EC2_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$EC2_ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }'
fi
aws iam attach-role-policy --role-name "$EC2_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

cat > "$WORK/ec2-kinesis-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["kinesis:PutRecord", "kinesis:PutRecords", "kinesis:DescribeStream", "kinesis:DescribeStreamSummary"],
    "Resource": "$STREAM_ARN"
  }]
}
EOF
aws iam put-role-policy --role-name "$EC2_ROLE" --policy-name kinesis-write \
  --policy-document "file://$WORK/ec2-kinesis-policy.json"

if ! aws iam get-instance-profile --instance-profile-name "$EC2_ROLE" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$EC2_ROLE"
  aws iam add-role-to-instance-profile --instance-profile-name "$EC2_ROLE" --role-name "$EC2_ROLE"
else
  aws iam add-role-to-instance-profile --instance-profile-name "$EC2_ROLE" --role-name "$EC2_ROLE" 2>/dev/null || true
fi
echo "Waiting for IAM propagation..."
sleep 10

# --- IAM Flink Role ---
FLINK_ROLE="wsc2026-analytics-flink-role"
if ! aws iam get-role --role-name "$FLINK_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$FLINK_ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"kinesisanalytics.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }'
fi
cat > "$WORK/flink-kinesis-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream", "kinesis:DescribeStreamSummary",
        "kinesis:GetRecords", "kinesis:GetShardIterator",
        "kinesis:ListShards", "kinesis:SubscribeToShard"
      ],
      "Resource": "$STREAM_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
        "logs:DescribeLogGroups", "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF
aws iam put-role-policy --role-name "$FLINK_ROLE" --policy-name kinesis-read \
  --policy-document "file://$WORK/flink-kinesis-policy.json"
FLINK_ROLE_ARN=$(aws iam get-role --role-name "$FLINK_ROLE" --query 'Role.Arn' --output text)

# --- Security Groups ---
ALB_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=wsc2026-analytics-alb-sg" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
if [ "$ALB_SG" = "None" ] || [ -z "$ALB_SG" ]; then
  ALB_SG=$(aws ec2 create-security-group --group-name wsc2026-analytics-alb-sg --description "ALB SG for analytics" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
  tag_resource "$ALB_SG" "wsc2026-analytics-alb-sg"
  aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0 2>/dev/null || true
fi

EC2_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=wsc2026-analytics-ec2-sg" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
if [ "$EC2_SG" = "None" ] || [ -z "$EC2_SG" ]; then
  EC2_SG=$(aws ec2 create-security-group --group-name wsc2026-analytics-ec2-sg --description "EC2 SG for analytics app" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
  tag_resource "$EC2_SG" "wsc2026-analytics-ec2-sg"
  aws ec2 authorize-security-group-ingress --group-id "$EC2_SG" --protocol tcp --port 5000 --source-group "$ALB_SG" 2>/dev/null || true
  aws ec2 authorize-security-group-egress --group-id "$EC2_SG" --protocol -1 --port all --cidr 0.0.0.0/0 2>/dev/null || true
else
  aws ec2 authorize-security-group-ingress --group-id "$EC2_SG" --protocol tcp --port 5000 --source-group "$ALB_SG" 2>/dev/null || true
fi

# --- User Data ---
python3 <<PY > "$WORK/user-data.sh"
import pathlib
app = pathlib.Path("$BASE/app.py").read_text()
req = pathlib.Path("$BASE/requirements.txt").read_text()
print(f'''#!/bin/bash
set -ex
exec > /var/log/user-data.log 2>&1
dnf install -y python3.12 python3.12-pip
mkdir -p /opt/app
cat > /opt/app/app.py <<'APP_EOF'
{app}APP_EOF
cat > /opt/app/requirements.txt <<'REQ_EOF'
{req}REQ_EOF
python3.12 -m pip install --upgrade pip
python3.12 -m pip install -r /opt/app/requirements.txt
cat > /etc/systemd/system/app.service <<'UNIT_EOF'
[Unit]
Description=Analytics Flask App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=STREAM_NAME=wsc2026-order-stream
Environment=AWS_REGION=ap-northeast-2
WorkingDirectory=/opt/app
ExecStart=/usr/bin/python3.12 -m gunicorn -w 2 -b 0.0.0.0:5000 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT_EOF
systemctl daemon-reload
systemctl enable app
systemctl start app
''')
PY

# --- EC2 ---
AMI=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)

EC2_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=wsc2026-analytics-ec2" "Name=instance-state-name,Values=running,pending,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "None")

if [ "$EC2_ID" = "None" ] || [ -z "$EC2_ID" ]; then
  EC2_ID=$(aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type t3.small \
    --subnet-id "$PRIV_A" \
    --security-group-ids "$EC2_SG" \
    --iam-instance-profile Name="$EC2_ROLE" \
    --user-data "file://$WORK/user-data.sh" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=wsc2026-analytics-ec2}]" \
    --query 'Instances[0].InstanceId' --output text)
  echo "Launched EC2 $EC2_ID"
else
  echo "EC2 exists: $EC2_ID"
fi

echo "Waiting for EC2 running..."
aws ec2 wait instance-running --instance-ids "$EC2_ID"

# --- ALB ---
ALB_ARN=$(aws elbv2 describe-load-balancers --names wsc2026-analytics-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "None")
if [ "$ALB_ARN" = "None" ] || [ -z "$ALB_ARN" ]; then
  ALB_ARN=$(aws elbv2 create-load-balancer \
    --name wsc2026-analytics-alb \
    --subnets "$PUB_A" "$PUB_B" \
    --security-groups "$ALB_SG" \
    --scheme internet-facing \
    --type application \
    --tags Key=Name,Value=wsc2026-analytics-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
  echo "Created ALB"
else
  echo "ALB exists"
fi
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text)

TG_ARN=$(aws elbv2 describe-target-groups --names wsc2026-analytics-tg --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "None")
if [ "$TG_ARN" = "None" ] || [ -z "$TG_ARN" ]; then
  TG_ARN=$(aws elbv2 create-target-group \
    --name wsc2026-analytics-tg \
    --protocol HTTP \
    --port 5000 \
    --vpc-id "$VPC_ID" \
    --health-check-path /health \
    --health-check-protocol HTTP \
    --target-type instance \
    --tags Key=Name,Value=wsc2026-analytics-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
  echo "Created target group"
fi

LISTENER=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query 'Listeners[?Port==`80`].ListenerArn' --output text 2>/dev/null || true)
if [ -z "$LISTENER" ] || [ "$LISTENER" = "None" ]; then
  aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null
  echo "Created listener"
fi

aws elbv2 register-targets --target-group-arn "$TG_ARN" --targets Id="$EC2_ID" 2>/dev/null || true

echo "Waiting for target healthy..."
for i in $(seq 1 60); do
  STATE=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --targets Id="$EC2_ID" \
    --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text 2>/dev/null || echo "unknown")
  echo "  target health: $STATE"
  [ "$STATE" = "healthy" ] && break
  sleep 10
done

# --- Flink Studio ---
if ! aws kinesisanalyticsv2 describe-application --application-name wsc2026-analytics-flink >/dev/null 2>&1; then
  # Try STUDIO mode first (per assignment), fall back to INTERACTIVE (AWS API)
  if ! aws kinesisanalyticsv2 create-application \
    --application-name wsc2026-analytics-flink \
    --runtime-environment ZEPPELIN-FLINK-3_0 \
    --application-mode STUDIO \
    --service-execution-role "$FLINK_ROLE_ARN" 2>"$WORK/flink-create.err"; then
    echo "STUDIO mode failed, trying INTERACTIVE..."
    cat "$WORK/flink-create.err" || true
    aws kinesisanalyticsv2 create-application \
      --application-name wsc2026-analytics-flink \
      --runtime-environment ZEPPELIN-FLINK-3_0 \
      --application-mode INTERACTIVE \
      --service-execution-role "$FLINK_ROLE_ARN"
  fi
  echo "Created Flink application"
else
  echo "Flink application exists"
fi

echo "Waiting for Flink READY..."
for i in $(seq 1 30); do
  FSTATUS=$(aws kinesisanalyticsv2 describe-application --application-name wsc2026-analytics-flink \
    --query 'ApplicationDetail.ApplicationStatus' --output text 2>/dev/null || echo "UNKNOWN")
  echo "  Flink status: $FSTATUS"
  [ "$FSTATUS" = "READY" ] && break
  sleep 10
done

echo ""
echo "=== Deploy complete ==="
echo "VPC_ID=$VPC_ID"
echo "EC2_ID=$EC2_ID"
echo "ALB_DNS=$ALB_DNS"
echo "STREAM_ARN=$STREAM_ARN"
echo "FLINK_STATUS=$FSTATUS"
