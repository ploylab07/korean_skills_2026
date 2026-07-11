#!/bin/bash

#2-1 EKS Scaling
#2-1과제의 채점은 Bastion에서 진행합니다.

# 사전 준비
aws configure set region ap-northeast-2
aws eks update-kubeconfig --region ap-northeast-2 --name wsc-scaling-cluster

echo ====================
echo "       1-1        "
echo ====================

VPC_ID=$(aws ec2 describe-vpcs \
  --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=wsc-scaling-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

aws ec2 describe-subnets \
  --region ap-northeast-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].[Tags[?Key=='Name']|[0].Value,AvailabilityZone,CidrBlock]" \
  --output text
  
aws ec2 describe-instances \
  --region ap-northeast-2 \
  --filters \
    "Name=tag:Name,Values=wsc-scaling-bastion" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].[Tags[?Key=='Name']|[0].Value,InstanceType]" \
  --output text

aws sqs list-queues \
  --query "QueueUrls[?contains(@, 'wsc-scaling-sqs')]" \
  --output text \
| awk -F'/' '{print $NF}'

echo

echo ====================
echo "       1-2        "
echo ====================

aws eks describe-cluster \
  --region ap-northeast-2 \
  --name wsc-scaling-cluster \
  --query "cluster.{name:name,version:version}" \
  --output text

echo

echo ====================
echo "       1-3        "
echo ====================

aws eks describe-nodegroup \
  --region ap-northeast-2 \
  --cluster-name wsc-scaling-cluster \
  --nodegroup-name wsc-scaling-node \
  --query "nodegroup.{nodegroupName:nodegroupName, instanceTypes:join(',', instanceTypes)}" \
  --output text

aws eks describe-nodegroup \
  --region ap-northeast-2 \
  --cluster-name wsc-scaling-cluster \
  --nodegroup-name wsc-scaling-node \
  --query "nodegroup.scalingConfig" \
  --output text | tr '\t' '\n' | sort -n

aws eks describe-nodegroup \
  --region ap-northeast-2 \
  --cluster-name wsc-scaling-cluster \
  --nodegroup-name wsc-scaling-node \
  --query "nodegroup.labels.dedicated" \
  --output text

echo ====================
echo "       1-4        "
echo ====================

kubectl get namespace wsc-scaling

kubectl get deployment wsc-scaling-deploy -n wsc-scaling

kubectl get deployment wsc-scaling-deploy -n wsc-scaling \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

echo ====================
echo "       1-5        "
echo ====================

kubectl get scaledobject wsc-scaling-scaledobject -n wsc-scaling \
  -o jsonpath='{.spec.pollingInterval}'; echo

kubectl get scaledobject wsc-scaling-scaledobject -n wsc-scaling \
  -o jsonpath='{.spec.triggers[0].metadata.queueLength}'; echo

echo ====================
echo "       1-6        "
echo ====================

echo "Manual"