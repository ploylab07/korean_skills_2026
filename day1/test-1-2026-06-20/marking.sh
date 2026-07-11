echo "============================="
rm -rf ~/.aws
mkdir -p ~/.aws
aws configure set region ap-northeast-2
echo "사전준비 완료! 채점 시작!"

echo -e "============1-1-A============"
aws ec2 describe-vpcs --filter Name=tag:Name,Values=gj2025-hub-vpc --query "Vpcs[0].CidrBlock"
aws ec2 describe-vpcs --filter Name=tag:Name,Values=gj2025-app-vpc --query "Vpcs[0].CidrBlock" 

echo -e "\n============1-2-A============"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-hub-public-subnet-a --query "Subnets[0].CidrBlock"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-hub-public-subnet-b --query "Subnets[0].CidrBlock"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-hub-private-subnet-a --query "Subnets[0].CidrBlock"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-hub-private-subnet-b --query "Subnets[0].CidrBlock"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-hub-firewall-subnet --query "Subnets[0].CidrBlock" 

echo -e "\n============1-2-B============"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-app-private-subnet-a --query "Subnets[0].CidrBlock"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-app-private-subnet-b --query "Subnets[0].CidrBlock"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-app-data-subnet-a --query "Subnets[0].CidrBlock"
aws ec2 describe-subnets --filter Name=tag:Name,Values=gj2025-app-data-subnet-b --query "Subnets[0].CidrBlock"

echo -e "\n============1-3-A============"
aws ec2 describe-route-tables --filters "Name=tag:Name,Values=gj2025-hub-public-rtb" --query "RouteTables[].Routes[?GatewayId != null && starts_with(GatewayId, 'igw')].GatewayId" --output text \
; aws ec2 describe-route-tables --filters "Name=tag:Name,Values=gj2025-hub-firewall-rtb" --query "RouteTables[].Routes[?NatGatewayId != null].NatGatewayId" --output text \
; aws ec2 describe-route-tables --filters "Name=tag:Name,Values=gj2025-app-data-rtb-a" --query "RouteTables[].Associations[].SubnetId" --output text | xargs -I {} aws ec2 describe-subnets --subnet-ids {} --query "Subnets[].Tags[?Key=='Name'].Value" --output text \
; aws ec2 describe-route-tables --filters "Name=tag:Name,Values=gj2025-app-data-rtb-b" --query "RouteTables[].Associations[].SubnetId" --output text | xargs -I {} aws ec2 describe-subnets --subnet-ids {} --query "Subnets[].Tags[?Key=='Name'].Value" --output text

echo -e "\n============2-1-A============"
TGWS=$(aws ec2 describe-transit-gateways --query "TransitGateways[*].{Name:Tags[?Key=='Name'].Value|[0]}" --output json)
TGW_NAMES=$(echo $TGWS | jq -r '.[].Name')
for TGW_NAME in $TGW_NAMES; do
    echo "$TGW_NAME"
    TGW_ID=$(aws ec2 describe-transit-gateways --filters "Name=tag:Name,Values=$TGW_NAME" --query "TransitGateways[0].TransitGatewayId" --output text)
    ATTACHMENTS=$(aws ec2 describe-transit-gateway-attachments --filters "Name=transit-gateway-id,Values=$TGW_ID" --query "TransitGatewayAttachments[*].{Name:Tags[?Key=='Name'].Value|[0]}" --output json)
    ATTACHMENT_NAMES=$(echo $ATTACHMENTS | jq -r '.[].Name')
    for ATTACHMENT_NAME in $ATTACHMENT_NAMES; do
        echo "$ATTACHMENT_NAME"
    done  
done

echo -e "\n============3-1-A============"
APP_EXTERNAL_NLB=$(aws elbv2 describe-load-balancers \
--names gj2025-app-external-nlb \
--query "LoadBalancers[].DNSName" \
--output text) && \
id_red=$(curl -s -H "Content-Type: application/json" -d '{"name":"kim"}' http://$APP_EXTERNAL_NLB/red | jq -r '.id') && \
curl -s http://$APP_EXTERNAL_NLB/red?id=$id_red

echo -e "\n============3-2-A============"
APP_EXTERNAL_NLB=$(aws elbv2 describe-load-balancers \
--names gj2025-app-external-nlb \
--query "LoadBalancers[].DNSName" \
--output text) && \
id_green=$(curl -s -H "Content-Type: application/json" -d '{"x":"abcd","y":21}' http://$APP_EXTERNAL_NLB/green | jq -r '.id') && \
curl -s http://$APP_EXTERNAL_NLB/green?id=$id_green

echo -e "\n============4-1-A============"
firewall_info=$(aws network-firewall describe-firewall --firewall-name gj2025-firewall)
echo "$firewall_info" | jq -r '.Firewall.SubnetMappings[] | "ID: \(.SubnetId)"' | while read -r subnet_info; do
  subnet_id=$(echo "$subnet_info" | awk '{print $2}')
  subnet_name=$(aws ec2 describe-subnets \
    --subnet-ids "$subnet_id" \
    --query 'Subnets[*].Tags[?Key==`Name`].Value' \
    --output text)
  echo "$subnet_name"
done

echo -e "\n============4-2-A============"
aws network-firewall describe-firewall --firewall-name gj2025-firewall --query "FirewallStatus.Status" --output text
aws network-firewall describe-logging-configuration \
  --firewall-name gj2025-firewall \
  --query 'LoggingConfiguration.LogDestinationConfigs' \
  --output json | jq -r '.[] | "\(.LogType)\n\(.LogDestinationType)\n\(.LogDestination.logGroup)\n"'

echo -e "\n============4-3-A============"
aws network-firewall describe-firewall-policy --firewall-policy-name gj2025-firewall-policy --query 'FirewallPolicyResponse.{FirewallPolicyName: FirewallPolicyName}' --output text
arn=$(aws network-firewall list-rule-groups --query "RuleGroups[?contains(Name, 'gj2025-firewall-rule')].Arn" --output text)
aws network-firewall describe-rule-group --rule-group-arn $arn --query 'RuleGroup.RulesSource.RulesString' --output text | grep -q . && echo "Suricata"

echo -e "\n============4-4-A============"
kubectl run firewall-test   --image=radial/busyboxplus   --restart=Never   --command -- sh -c "while true;
do sleep 3600; done" > /dev/null 2>&1
sleep 3
aws ec2 describe-subnets   --subnet-ids $(aws ec2 describe-instances \
    --instance-ids $(kubectl get node $(kubectl get pod firewall-test -n default -o jsonpath='{.spec.nodeName}') \
      -o jsonpath='{.spec.providerID}' | awk -F'/' '{print $5}') \
    --query 'Reservations[0].Instances[0].SubnetId' --output text)   --query "Subnets[0].Tags[?Key=='Name'].Value" --output text
kubectl exec firewall-test -- curl -m 5 -sS https://ifconfig.io

echo -e "\n============5-1-A============"
aws rds describe-db-instances \
  --query "DBInstances[*].[DBInstanceIdentifier, DBInstanceClass, MasterUsername, Endpoint.Port, Engine, EngineVersion, join(',', EnabledCloudwatchLogsExports)]" \
  --output text | tr '\t' '\n'
for id in $(aws rds describe-db-instances --query "DBInstances[*].DBSubnetGroup.Subnets[*].SubnetIdentifier" --output text); do
  aws ec2 describe-subnets --subnet-ids "$id" --query "Subnets[0].Tags[?Key=='Name'].Value | [0]" --output text
done

echo -e "\n============5-2-A============"
kubectl run proxy-test --image=mysql:8 --restart=Never -- sleep 60 &>/dev/null
sleep 3
ENDPOINT=$(aws rds describe-db-proxies --db-proxy-name gj2025-rds-proxy --query 'DBProxies[0].Endpoint' --output text)
SUBNET_ID=$(aws ec2 describe-instances --instance-ids $(kubectl get node $(kubectl get pod proxy-test -o jsonpath='{.spec.nodeName}') -o jsonpath='{.spec.providerID}' | cut -d'/' -f5) --query 'Reservations[0].Instances[0].SubnetId' --output text)
aws ec2 describe-subnets --subnet-ids $SUBNET_ID --query 'Subnets[0].Tags[?Key==`Name`].Value' --output text
kubectl exec proxy-test -- mysql -h $ENDPOINT -u admin -pSkills53#\$% -e 'SELECT 1' &>/dev/null && echo True || echo False

echo -e "\n============6-1-A============"
aws ecr describe-repositories \
--output json \
| jq -r '.repositories[] | "\(.repositoryName)\n\(.encryptionConfiguration.encryptionType)"'

echo -e "\n============7-1-A============"
aws eks describe-cluster   \
--name gj2025-eks-cluster   \
--query 'cluster.[version, logging.clusterLogging[*].types]'   \
--output text | awk 'NR==1{print $0; next} {gsub(/\t/, "\n"); print}'

echo -e "\n============7-2-A============"
aws eks describe-nodegroup --cluster-name gj2025-eks-cluster --nodegroup-name gj2025-eks-addon-nodegroup --query 'nodegroup.{NodeGroupName:nodegroupName, Status:status, DesiredSize:scalingConfig.desiredSize, InstanceTypes:instanceTypes}' --output json \
; aws eks describe-nodegroup --cluster-name gj2025-eks-cluster --nodegroup-name gj2025-eks-app-nodegroup --query 'nodegroup.{NodeGroupName:nodegroupName, Status:status, DesiredSize:scalingConfig.desiredSize, InstanceTypes:instanceTypes}' --output json \
; aws ec2 describe-instances --instance-ids $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $(aws eks describe-nodegroup --cluster-name gj2025-eks-cluster --nodegroup-name gj2025-eks-addon-nodegroup --query 'nodegroup.resources.autoScalingGroups[0].name' --output text) --query 'AutoScalingGroups[0].Instances[].InstanceId' --output text) --query 'Reservations[].Instances[].Tags[?Key==`Name`].Value | []' --output text \
; aws ec2 describe-instances --instance-ids $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $(aws eks describe-nodegroup --cluster-name gj2025-eks-cluster --nodegroup-name gj2025-eks-app-nodegroup --query 'nodegroup.resources.autoScalingGroups[0].name' --output text) --query 'AutoScalingGroups[0].Instances[].InstanceId' --output text) --query 'Reservations[].Instances[].Tags[?Key==`Name`].Value | []' --output text

echo -e "\n============7-3-A============"
kubectl get rollout red-rollout \
-n skills \
| awk 'NR==2 {print $1; if ($2 == $3 && $2 > 0) print "True"; else print "False"}'
kubectl get rollout green-rollout \
-n skills \
| awk 'NR==2 {print $1; if ($2 == $3 && $2 > 0) print "True"; else print "False"}'

echo -e "\n============7-4-A============"
kubectl get externalsecret db-secret -n skills | awk 'NR==2 {print $(NF-1) "\n" $NF}'

echo -e "\n============8-1-A============"
aws secretsmanager describe-secret --secret-id gj2025-eks-cluster-catalog-secret --region ap-northeast-2 --query "Name" --output text
aws secretsmanager describe-secret --secret-id gj2025-github-token --region ap-northeast-2 --query "Name" --output text

echo -e "\n============8-2-A============"
for arn in $(aws iam list-attached-role-policies --role-name $(kubectl get sa $(kubectl get secretstore $(kubectl get externalsecret db-secret -n skills -o jsonpath="{.spec.secretStoreRef.name}") -n skills -o jsonpath="{.spec.provider.aws.auth.jwt.serviceAccountRef.name}") -n skills -o jsonpath="{.metadata.annotations.eks\.amazonaws\.com/role-arn}" | awk -F '/' '{print $2}') --query 'AttachedPolicies[*].PolicyArn' --output text); do aws iam get-policy-version --policy-arn $arn --version-id $(aws iam get-policy --policy-arn $arn --query 'Policy.DefaultVersionId' --output text) --query 'PolicyVersion.Document.Statement[*].Resource' --output text; done | tr '\t' '\n'

echo -e "\n============9-1-A============"
kubectl get daemonset red-fluent-bit -n amazon-cloudwatch -o yaml > red-fluent-bit.yaml
kubectl delete daemonset red-fluent-bit -n amazon-cloudwatch > /dev/null 2>&1
date
aws logs delete-log-group --log-group-name /gj2025/app/red > /dev/null 2>&1
kubectl apply -f red-fluent-bit.yaml > /dev/null 2>&1
sleep 3
EXTERNAL_NLB=$(aws elbv2 describe-load-balancers \
  --names gj2025-app-external-nlb \
  --query "LoadBalancers[0].DNSName" \
  --output text)
curl -s -X POST -H "Content-Type: application/json" -d '{"name":"kim"}' http://$EXTERNAL_NLB/red > /dev/null 2>&1
sleep 3
aws logs get-log-events \
  --log-group-name /gj2025/app/red \
  --log-stream-name app-red-logs \
  --limit 1 \
  --query 'events[*].message' \
  --output json | jq -r '.[0] | fromjson | .log'

echo -e "\n============9-2-A============"
kubectl get daemonset green-fluent-bit -n amazon-cloudwatch -o yaml > green-fluent-bit.yaml
kubectl delete daemonset green-fluent-bit -n amazon-cloudwatch > /dev/null 2>&1
date
aws logs delete-log-group --log-group-name /gj2025/app/green > /dev/null 2>&1
kubectl apply -f green-fluent-bit.yaml > /dev/null 2>&1
sleep 3
EXTERNAL_NLB=$(aws elbv2 describe-load-balancers \
  --names gj2025-app-external-nlb \
  --query "LoadBalancers[0].DNSName" \
  --output text)
curl -s -X POST -H "Content-Type: application/json" -d '{"x":"abcd","y":21}' http://$EXTERNAL_NLB/green > /dev/null 2>&1 
sleep 3
aws logs get-log-events \
  --log-group-name /gj2025/app/green \
  --log-stream-name app-green-logs \
  --limit 1 \
  --query 'events[*].message' \
  --output json | jq -r '.[0] | fromjson | .log'

echo -e "\n============10-1-A============"
aws elbv2 describe-load-balancers --names gj2025-app-external-nlb \
--query 'LoadBalancers[0].Scheme' --output text && \
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$(aws elbv2 describe-load-balancers --names gj2025-app-external-nlb --query 'LoadBalancers[0].VpcId' --output text)" \
  --query "Tags[?Key=='Name'].Value | [0]" --output text
aws elbv2 describe-load-balancers --names gj2025-argo-external-nlb \
--query 'LoadBalancers[0].Scheme' --output text && \
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$(aws elbv2 describe-load-balancers --names gj2025-argo-external-nlb --query 'LoadBalancers[0].VpcId' --output text)" \
  --query "Tags[?Key=='Name'].Value | [0]" --output text

echo -e "\n============10-2-A============"
aws elbv2 describe-load-balancers --names gj2025-app-internal-nlb \
--query 'LoadBalancers[0].Scheme' --output text && \
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$(aws elbv2 describe-load-balancers --names gj2025-app-internal-nlb --query 'LoadBalancers[0].VpcId' --output text)" \
  --query "Tags[?Key=='Name'].Value | [0]" --output text
aws elbv2 describe-load-balancers --names gj2025-argo-internal-nlb \
--query 'LoadBalancers[0].Scheme' --output text && \
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$(aws elbv2 describe-load-balancers --names gj2025-argo-internal-nlb --query 'LoadBalancers[0].VpcId' --output text)" \
  --query "Tags[?Key=='Name'].Value | [0]" --output text
aws elbv2 describe-load-balancers --names gj2025-app-alb \
--query 'LoadBalancers[0].Scheme' --output text && \
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$(aws elbv2 describe-load-balancers --names gj2025-app-alb --query 'LoadBalancers[0].VpcId' --output text)" \
  --query "Tags[?Key=='Name'].Value | [0]" --output text

echo -e "\n============11-1-A============"
aws codebuild batch-get-projects --names gj2025-app-red-build --query "projects[0].[ \
    source.type, \
    source.location, \
    source.auth.type, \
    environment.environmentVariables[].type, \
    logsConfig.cloudWatchLogs.groupName]" --output text | xargs -n1
 aws codebuild batch-get-projects --names gj2025-app-green-build --query "projects[0].[ \
    source.type, \
    source.location, \
    source.auth.type, \
    environment.environmentVariables[].type, \
    logsConfig.cloudWatchLogs.groupName]" --output text | xargs -n1

echo -e "\n============11-2-A============"
aws codepipeline get-pipeline \
--name gj2025-app-red-pipeline  \
--query 'pipeline.[stages[?name==`Source`].actions[0].[actionTypeId.provider, configuration.[OAuthToken != null, Repo]], stages[?name==`Build`].actions[0].configuration.ProjectName]' \
--output text | tr '\t' '\n'\
; aws codepipeline get-pipeline \
--name gj2025-app-green-pipeline  \
--query 'pipeline.[stages[?name==`Source`].actions[0].[actionTypeId.provider, configuration.[OAuthToken != null, Repo]], stages[?name==`Build`].actions[0].configuration.ProjectName]' \
--output text | tr '\t' '\n'

echo -e "\n============12-1-A============"
echo "채점지를 사용하여 채점합니다."

echo -e "\n============12-2-A============"
kubectl argo rollouts get rollout red-rollout -n skills | egrep "Strategy" \
; kubectl argo rollouts get rollout red-rollout -n skills | egrep "stable" | grep "Healthy" | awk {'print $6,$8'}
kubectl argo rollouts get rollout green-rollout -n skills | egrep "Strategy" \
; kubectl argo rollouts get rollout green-rollout -n skills | egrep "stable" | grep "Healthy" | awk {'print $6,$8'}

echo -e "\n============12-3-A============"
echo "채점지를 사용하여 채점합니다."

echo -e "\n============12-4-A============"
echo "채점지를 사용하여 채점합니다."
