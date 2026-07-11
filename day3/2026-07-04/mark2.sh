#!/bin/bash

#2-2 VPC Lattice
#2-2 과제의 채점은 Bastion에서 진행합니다.

#사전 준비
aws configure set region ap-southeast-1

echo ====================
echo "       2-1        "
echo ====================

aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=wsc-hub-vpc,wsc-spoke-vpc" \
  --query "Vpcs[*].[Tags[?Key=='Name']|[0].Value, CidrBlock]" \
  --output text

aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=wsc-hub-sn-pub-a,wsc-hub-sn-pub-c,wsc-spoke-sn-pub-a,wsc-spoke-sn-pub-c,wsc-spoke-sn-priv-a,wsc-spoke-sn-priv-c" \
  --query "Subnets[*].[Tags[?Key=='Name']|[0].Value, CidrBlock]" \
  --output text

aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=wsc-hub-bastion,wsc-spoke-app-v1,wsc-spoke-app-v2" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceType]" \
  --output text

echo""

echo ====================
echo "       2-2        "
echo ====================

aws elbv2 describe-load-balancers \
  --names wsc-spoke-app-alb \
  --query "LoadBalancers[].[LoadBalancerName,Scheme,Type,State.Code]" \
  --output text

aws elbv2 describe-target-groups \
  --names wsc-spoke-v1-tg wsc-spoke-v2-tg \
  --query "TargetGroups[].[TargetGroupName,Protocol,Port]" \
  --output text

echo""


echo ====================
echo "       2-3        "
echo ====================

aws vpc-lattice list-service-networks \
  --query "items[?name=='wsc-app-service-network'].name" \
  --output text

aws vpc-lattice list-services \
  --query "items[?name=='wsc-app-service'].name" \
  --output text

SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
  --query "items[?name=='wsc-app-service-network'].id" \
  --output text)

aws vpc-lattice list-service-network-vpc-associations \
  --service-network-identifier "$SERVICE_NETWORK_ID" \
  --query "items[].vpcId" \
  --output text \
| tr '\t' '\n' \
| while read -r vpc_id; do
    aws ec2 describe-vpcs \
      --vpc-ids "$vpc_id" \
      --query "Vpcs[0].Tags[?Key=='Name'].Value" \
      --output text
  done

echo""


echo ====================
echo "       2-4        "
echo ====================

SVC_ID=$(aws vpc-lattice list-services \
  --query "items[?name=='wsc-app-service'].id" \
  --output text)

LISTENER_ID=$(aws vpc-lattice list-listeners \
  --service-identifier "$SVC_ID" \
  --query "items[0].id" \
  --output text)

for RULE_ID in $(aws vpc-lattice list-rules \
  --service-identifier "$SVC_ID" \
  --listener-identifier "$LISTENER_ID" \
  --query "items[*].id" \
  --output text); do

  RULE=$(aws vpc-lattice get-rule \
    --service-identifier "$SVC_ID" \
    --listener-identifier "$LISTENER_ID" \
    --rule-identifier "$RULE_ID" \
    --output json)

  PRIORITY=$(echo "$RULE" | jq -r '.priority')

  if [ "$PRIORITY" != "99999" ]; then
    continue
  fi

  HEADER=$(echo "$RULE" | jq -r '.match.httpMatch.headerMatches[0].match.exact // "default"')

  TARGETS=$(echo "$RULE" \
    | jq -r '.action.forward.targetGroups[] | "\(.targetGroupIdentifier):\(.weight)"' \
    | while read -r line; do
        TG_ID=$(echo "$line" | cut -d: -f1)
        WEIGHT=$(echo "$line" | cut -d: -f2)

        TG_NAME=$(aws vpc-lattice get-target-group \
          --target-group-identifier "$TG_ID" \
          --query "name" \
          --output text)

        echo -n "$TG_NAME:$WEIGHT "
      done)

  echo "Priority=$PRIORITY | Header=$HEADER | Targets=$TARGETS"
done

echo""


echo ====================
echo "       2-5        "
echo ====================

for RULE_ID in $(aws vpc-lattice list-rules \
  --service-identifier "$SVC_ID" \
  --listener-identifier "$LISTENER_ID" \
  --query "items[*].id" \
  --output text); do

  RULE=$(aws vpc-lattice get-rule \
    --service-identifier "$SVC_ID" \
    --listener-identifier "$LISTENER_ID" \
    --rule-identifier "$RULE_ID" \
    --output json)

  PRIORITY=$(echo "$RULE" | jq -r '.priority')

  if [ "$PRIORITY" = "99999" ]; then
    continue
  fi

  HEADER=$(echo "$RULE" | jq -r '.match.httpMatch.headerMatches[0].match.exact // "default"')

  TARGETS=$(echo "$RULE" \
    | jq -r '.action.forward.targetGroups[] | "\(.targetGroupIdentifier):\(.weight)"' \
    | while read -r line; do
        TG_ID=$(echo "$line" | cut -d: -f1)
        WEIGHT=$(echo "$line" | cut -d: -f2)

        TG_NAME=$(aws vpc-lattice get-target-group \
          --target-group-identifier "$TG_ID" \
          --query "name" \
          --output text)

        echo -n "$TG_NAME:$WEIGHT "
      done)

  echo "Priority=$PRIORITY | Header=$HEADER | Targets=$TARGETS"
done

echo""

echo ====================
echo "       2-6        "
echo ====================

for TG_NAME in wsc-spoke-v1-tg wsc-spoke-v2-tg; do
  TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)

  STATUS=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --query "TargetHealthDescriptions[0].TargetHealth.State" \
    --output text)

  echo "$TG_NAME  $STATUS"
done

SVC_ID=$(aws vpc-lattice list-services \
  --query "items[?name=='wsc-app-service'].id" \
  --output text)

LATTICE_DNS=$(aws vpc-lattice get-service \
  --service-identifier "$SVC_ID" \
  --query "dnsEntry.domainName" \
  --output text)

curl -s -H "version: v1" http://$LATTICE_DNS/version

curl -s -H "version: v2" http://$LATTICE_DNS/version