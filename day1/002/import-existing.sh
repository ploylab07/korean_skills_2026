#!/usr/bin/env bash
# Import existing day1/002 AWS resources into Terraform state.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
set -a; source "$ROOT/.env"; set +a
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/wskorea26.yaml}"

source scripts/ids.env

TF="$ROOT/terraform"
$TF -chdir="$(pwd)" init -input=false >/dev/null

imp() {
  local addr="$1" id="$2"
  if $TF -chdir="$(pwd)" state list 2>/dev/null | grep -qxF "$addr"; then
    echo "skip $addr"
  else
    echo "import $addr <= $id"
    if $TF -chdir="$(pwd)" import -input=false "$addr" "$id" 2>/tmp/tf-imp-err.txt; then
      echo "  ok"
    else
      echo "  FAIL: $(tail -3 /tmp/tf-imp-err.txt | tr '\n' ' ')"
    fi
  fi
}

# Fix IMDS hop on app nodes for pod credentials
for id in $(aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=wskorea26-cluster" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text); do
  aws ec2 modify-instance-metadata-options --instance-id "$id" --http-put-response-hop-limit 2 --http-tokens required >/dev/null || true
done

imp aws_vpc.main "$VPC_ID"
imp aws_internet_gateway.main "$IGW_ID"
imp aws_subnet.pub_c "$PUB_C"
imp aws_subnet.pub_d "$PUB_D"
imp aws_subnet.priv_c "$PRIV_C"
imp aws_subnet.priv_d "$PRIV_D"
imp aws_eip.nat_c "$EIP_C"
imp aws_eip.nat_d "$EIP_D"
imp aws_nat_gateway.nat_c "$NGW_C"
imp aws_nat_gateway.nat_d "$NGW_D"
imp aws_route_table.public "$PUB_RTB"
imp aws_route_table.private_c "$PRIV_RTB_C"
imp aws_route_table.private_d "$PRIV_RTB_D"
imp aws_route.public_igw "${PUB_RTB}_0.0.0.0/0"
imp aws_route.private_c_nat "${PRIV_RTB_C}_0.0.0.0/0"
imp aws_route.private_d_nat "${PRIV_RTB_D}_0.0.0.0/0"
imp aws_route_table_association.pub_c "${PUB_C}/${PUB_RTB}"
imp aws_route_table_association.pub_d "${PUB_D}/${PUB_RTB}"
imp aws_route_table_association.priv_c "${PRIV_C}/${PRIV_RTB_C}"
imp aws_route_table_association.priv_d "${PRIV_D}/${PRIV_RTB_D}"

imp aws_security_group.env "$ENV_SG"
imp aws_security_group.eks_cluster "$CLUSTER_SG"
imp aws_security_group.alb "$ALB_SG"
GRAFANA_SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=wskorea26-grafana-alb-sg Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)
imp aws_security_group.grafana_alb "$GRAFANA_SG"

imp aws_kms_key.s3 "$S3_KEY"
imp aws_kms_key.dynamodb "$DDB_KEY"
imp aws_kms_key.eks "$EKS_KEY"
imp aws_kms_key.ecr "$ECR_KEY"
imp aws_kms_alias.s3 alias/wskorea26-s3-key
imp aws_kms_alias.dynamodb alias/wskorea26-dynamodb-key
imp aws_kms_alias.eks alias/wskorea26-eks-key
imp aws_kms_alias.ecr alias/wskorea26-ecr-key

imp aws_s3_bucket.web "$BUCKET"
imp aws_s3_bucket_public_access_block.web "$BUCKET"
imp aws_s3_bucket_server_side_encryption_configuration.web "$BUCKET"
imp aws_s3_object.index "${BUCKET}/web/main/index.html"
imp aws_s3_object.main_jpeg "${BUCKET}/web/main/main.jpeg"
imp aws_cloudfront_origin_access_control.s3 "$OAC_ID"

imp aws_ecr_repository.book wskorea26-book-repo
imp aws_dynamodb_table.data wskorea26-data-table

imp aws_iam_role.eks_cluster wskorea26-eks-cluster-role
imp aws_iam_role.eks_node wskorea26-eks-node-role
imp aws_iam_role.lambda wskorea26-book-lambda-role
imp aws_iam_role_policy_attachment.eks_cluster_policy "wskorea26-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
imp aws_iam_role_policy_attachment.eks_vpc_controller "wskorea26-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
imp aws_iam_role_policy_attachment.node_worker "wskorea26-eks-node-role/arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
imp aws_iam_role_policy_attachment.node_cni "wskorea26-eks-node-role/arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
imp aws_iam_role_policy_attachment.node_ecr "wskorea26-eks-node-role/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
imp aws_iam_role_policy_attachment.node_ssm "wskorea26-eks-node-role/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
imp aws_iam_role_policy_attachment.node_cw "wskorea26-eks-node-role/arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
imp aws_iam_role_policy_attachment.lambda_basic "wskorea26-book-lambda-role/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
imp aws_iam_role_policy.node_ddb "wskorea26-eks-node-role:ddb-access"
imp aws_iam_role_policy.lambda_ddb "wskorea26-book-lambda-role:ddb-access"

imp aws_eks_cluster.main wskorea26-cluster
imp aws_eks_node_group.addon wskorea26-cluster:wskorea26-addon-ng
imp aws_eks_node_group.app wskorea26-cluster:wskorea26-app-ng

imp aws_lambda_function.book wskorea26-book-lambda

imp aws_lb.book "$ALB_ARN"
imp aws_lb_target_group.book "$BOOK_TG"
imp aws_lb_target_group.lambda "$LAMBDA_TG"
imp aws_lb_listener.book "$LISTENER_ARN"
imp aws_lb_listener_rule.post_book arn:aws:elasticloadbalancing:ap-northeast-2:163389715563:listener-rule/app/wskorea26-book-alb/c33541ba37d18900/fe13a35654e8c843/b7a8c4ef13ef2499
imp aws_lb_listener_rule.get_book arn:aws:elasticloadbalancing:ap-northeast-2:163389715563:listener-rule/app/wskorea26-book-alb/c33541ba37d18900/fe13a35654e8c843/d9b63e96b24f6684

GRAFANA_ALB_ARN=$(aws elbv2 describe-load-balancers --names wskorea26-grafana-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)
GRAFANA_TG=$(aws elbv2 describe-target-groups --names wskorea26-grafana-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
GRAFANA_LISTENER=$(aws elbv2 describe-listeners --load-balancer-arn "$GRAFANA_ALB_ARN" --query 'Listeners[0].ListenerArn' --output text)
imp aws_lb.grafana "$GRAFANA_ALB_ARN"
imp aws_lb_target_group.grafana "$GRAFANA_TG"
imp aws_lb_listener.grafana "$GRAFANA_LISTENER"

imp aws_cloudfront_function.rewrite wskorea26-book-rewrite
imp aws_cloudfront_distribution.main "$CF_ID"
imp aws_s3_bucket_policy.web "$BUCKET"

aws eks update-kubeconfig --region ap-northeast-2 --name wskorea26-cluster --alias wskorea26 --kubeconfig "$KUBECONFIG" >/dev/null
imp kubernetes_namespace.wskorea26 wskorea26
imp kubernetes_namespace.monitoring monitoring
imp kubernetes_deployment.book wskorea26/book
imp kubernetes_service.book wskorea26/book
imp kubernetes_config_map.dashboard monitoring/wskorea26-dashboard
imp helm_release.kube_prometheus_stack monitoring/kps
imp helm_release.fluent_bit monitoring/aws-for-fluent-bit

echo "IMPORT DONE — state count: $($TF -chdir="$(pwd)" state list | wc -l)"
