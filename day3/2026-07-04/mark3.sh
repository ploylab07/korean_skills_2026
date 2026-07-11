#!/bin/bash

#2-3 Container Logging
#2-3 과제의 채점은 Bastion에서 진행합니다.

#사전 준비
aws configure set region ap-northeast-1
aws eks update-kubeconfig --region ap-northeast-1 --name wsc-logging-cluster

#변수 지정
read -s -p "비번호를 입력하시오: " NM
echo  

echo ====================
echo "       3-1        "
echo ====================

aws ec2 describe-vpcs \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-vpc" \
  --query "Vpcs[0].CidrBlock" --output text


aws ec2 describe-subnets \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-sn-pub-a,wsc-logging-sn-pub-c,wsc-logging-sn-priv-a,wsc-logging-sn-priv-c" \
  --query "Subnets[*].[Tags[?Key=='Name'].Value|[0],CidrBlock]" \
  --output text

aws eks describe-cluster \
  --region ap-northeast-1 \
  --name wsc-logging-cluster \
  --query "cluster.[name,version]" \
  --output text

aws eks describe-nodegroup \
  --region ap-northeast-1 \
  --cluster-name wsc-logging-cluster \
  --nodegroup-name wsc-logging-ng \
  --query "nodegroup.[nodegroupName,scalingConfig]" \
  --output json

echo""
sleep 2

echo ====================
echo "       3-2        "
echo ====================

kubectl get pods -n wsc-logging -l app.kubernetes.io/name=loki,app.kubernetes.io/component=single-binary | awk '{ print $3 }'
kubectl get svc  -n wsc-logging -l app.kubernetes.io/name=loki | grep LoadBalancer | awk '{ print $4 }'
kubectl get pods -n wsc-logging -l app.kubernetes.io/name=grafana | awk '{ print $3 }'
kubectl get svc  -n wsc-logging -l app.kubernetes.io/name=grafana | grep LoadBalancer | awk '{ print $4 }'

echo""
sleep 2

echo ====================
echo "       3-3        "
echo ====================

EC2_IP=$(aws ec2 describe-instances \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-log-app-bastion" \
             "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
curl -s "http://$EC2_IP:5000/health"

echo""
sleep 2

echo ====================
echo "       3-4        "
echo ====================

INSTANCE_ID=$(aws ec2 describe-instances \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-log-app-bastion" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

CMD_ID=$(aws ssm send-command \
  --region ap-northeast-1 \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["systemctl is-active fluent-bit"]}' \
  --query "Command.CommandId" --output text)

sleep 5

aws ssm get-command-invocation \
  --region ap-northeast-1 \
  --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query "StandardOutputContent" --output text

echo""
sleep 2

echo ====================
echo "       3-5        "
echo ====================

EC2_IP=$(aws ec2 describe-instances \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-log-app-bastion" \
             "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
curl -s "http://$EC2_IP:5000/generate?count=30" > /dev/null 2>&1

sleep 10

LOKI_LB=$(kubectl get svc  -n wsc-logging -l app.kubernetes.io/name=loki | grep LoadBalancer | awk '{ print $4 }')
curl -sG "http://$LOKI_LB:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="wsc-app-log"}' \
  --data-urlencode 'limit=10' \
| python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',{}).get('result',[])), 'streams found')"\

echo""
sleep 2

echo ====================
echo "       3-6        "
echo ====================

echo "Manual"