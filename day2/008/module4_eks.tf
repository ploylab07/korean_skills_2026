############################################
# Module 4 — EKS / SQS / KEDA / Karpenter (us-west-2)
############################################

resource "aws_vpc" "sqs" {
  provider             = aws.oregon
  cidr_block           = "10.80.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "skills-sqs-vpc" })
}

resource "aws_internet_gateway" "sqs" {
  provider = aws.oregon
  vpc_id   = aws_vpc.sqs.id
  tags     = merge(local.common_tags, { Name = "skills-sqs-igw" })
}

resource "aws_subnet" "sqs_public_a" {
  provider                = aws.oregon
  vpc_id                  = aws_vpc.sqs.id
  cidr_block              = "10.80.1.0/24"
  availability_zone       = data.aws_availability_zones.oregon.names[0]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, {
    Name                     = "skills-sqs-public-a"
    "kubernetes.io/role/elb" = "1"
    "karpenter.sh/discovery" = "skills-sqs-cluster"
    "kubernetes.io/cluster/skills-sqs-cluster" = "shared"
  })
}

resource "aws_subnet" "sqs_public_b" {
  provider                = aws.oregon
  vpc_id                  = aws_vpc.sqs.id
  cidr_block              = "10.80.2.0/24"
  availability_zone       = data.aws_availability_zones.oregon.names[1]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, {
    Name                     = "skills-sqs-public-b"
    "kubernetes.io/role/elb" = "1"
    "karpenter.sh/discovery" = "skills-sqs-cluster"
    "kubernetes.io/cluster/skills-sqs-cluster" = "shared"
  })
}

resource "aws_subnet" "sqs_private_a" {
  provider          = aws.oregon
  vpc_id            = aws_vpc.sqs.id
  cidr_block        = "10.80.11.0/24"
  availability_zone = data.aws_availability_zones.oregon.names[0]
  tags = merge(local.common_tags, {
    Name                              = "skills-sqs-private-a"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = "skills-sqs-cluster"
    "kubernetes.io/cluster/skills-sqs-cluster" = "shared"
  })
}

resource "aws_subnet" "sqs_private_b" {
  provider          = aws.oregon
  vpc_id            = aws_vpc.sqs.id
  cidr_block        = "10.80.12.0/24"
  availability_zone = data.aws_availability_zones.oregon.names[1]
  tags = merge(local.common_tags, {
    Name                              = "skills-sqs-private-b"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = "skills-sqs-cluster"
    "kubernetes.io/cluster/skills-sqs-cluster" = "shared"
  })
}

resource "aws_route_table" "sqs_public" {
  provider = aws.oregon
  vpc_id   = aws_vpc.sqs.id
  tags     = merge(local.common_tags, { Name = "skills-sqs-public-rt" })
}

resource "aws_route" "sqs_public_default" {
  provider               = aws.oregon
  route_table_id         = aws_route_table.sqs_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.sqs.id
}

resource "aws_route_table_association" "sqs_public_a" {
  provider       = aws.oregon
  subnet_id      = aws_subnet.sqs_public_a.id
  route_table_id = aws_route_table.sqs_public.id
}

resource "aws_route_table_association" "sqs_public_b" {
  provider       = aws.oregon
  subnet_id      = aws_subnet.sqs_public_b.id
  route_table_id = aws_route_table.sqs_public.id
}

resource "aws_eip" "sqs_nat" {
  provider = aws.oregon
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "skills-sqs-nat-eip" })
}

resource "aws_nat_gateway" "sqs" {
  provider      = aws.oregon
  allocation_id = aws_eip.sqs_nat.id
  subnet_id     = aws_subnet.sqs_public_a.id
  tags          = merge(local.common_tags, { Name = "skills-sqs-nat" })
  depends_on    = [aws_internet_gateway.sqs]
}

resource "aws_route_table" "sqs_private" {
  provider = aws.oregon
  vpc_id   = aws_vpc.sqs.id
  tags     = merge(local.common_tags, { Name = "skills-sqs-private-rt" })
}

resource "aws_route" "sqs_private_default" {
  provider               = aws.oregon
  route_table_id         = aws_route_table.sqs_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.sqs.id
}

resource "aws_route_table_association" "sqs_private_a" {
  provider       = aws.oregon
  subnet_id      = aws_subnet.sqs_private_a.id
  route_table_id = aws_route_table.sqs_private.id
}

resource "aws_route_table_association" "sqs_private_b" {
  provider       = aws.oregon
  subnet_id      = aws_subnet.sqs_private_b.id
  route_table_id = aws_route_table.sqs_private.id
}

resource "aws_iam_role" "eks_cluster" {
  name = "skills-sqs-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_fargate" {
  name = "skills-sqs-fargate-pod-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_fargate" {
  role       = aws_iam_role.eks_fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_eks_cluster" "sqs" {
  provider = aws.oregon
  name     = "skills-sqs-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids              = [aws_subnet.sqs_public_a.id, aws_subnet.sqs_public_b.id, aws_subnet.sqs_private_a.id, aws_subnet.sqs_private_b.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
  tags       = local.common_tags
}

resource "aws_ec2_tag" "cluster_sg_discovery" {
  provider    = aws.oregon
  resource_id = aws_eks_cluster.sqs.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = "skills-sqs-cluster"
}

resource "aws_eks_fargate_profile" "keda" {
  provider               = aws.oregon
  cluster_name           = aws_eks_cluster.sqs.name
  fargate_profile_name   = "skills-sqs-fp-keda"
  pod_execution_role_arn = aws_iam_role.eks_fargate.arn
  subnet_ids             = [aws_subnet.sqs_private_a.id, aws_subnet.sqs_private_b.id]
  selector { namespace = "keda" }
}

resource "aws_eks_fargate_profile" "karpenter" {
  provider               = aws.oregon
  cluster_name           = aws_eks_cluster.sqs.name
  fargate_profile_name   = "skills-sqs-fp-karpenter"
  pod_execution_role_arn = aws_iam_role.eks_fargate.arn
  subnet_ids             = [aws_subnet.sqs_private_a.id, aws_subnet.sqs_private_b.id]
  selector { namespace = "karpenter" }
}

resource "aws_eks_fargate_profile" "coredns" {
  provider               = aws.oregon
  cluster_name           = aws_eks_cluster.sqs.name
  fargate_profile_name   = "skills-sqs-fp-coredns"
  pod_execution_role_arn = aws_iam_role.eks_fargate.arn
  subnet_ids             = [aws_subnet.sqs_private_a.id, aws_subnet.sqs_private_b.id]
  selector { namespace = "kube-system" }
}

resource "aws_sqs_queue" "skills" {
  provider                  = aws.oregon
  name                      = "skills-sqs-queue"
  visibility_timeout_seconds = 60
  tags                      = local.common_tags
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.sqs.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
  tags            = local.common_tags
}

locals {
  oidc_host = replace(aws_eks_cluster.sqs.identity[0].oidc[0].issuer, "https://", "")
}

resource "aws_iam_role" "karpenter_controller" {
  name = "skills-sqs-karpenter-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:karpenter:karpenter"
        }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "inline"
  role = aws_iam_role.karpenter_controller.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter", "ec2:DescribeImages", "ec2:RunInstances", "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups", "ec2:DescribeLaunchTemplates", "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes", "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeAvailabilityZones",
          "ec2:DeleteLaunchTemplate", "ec2:CreateTags", "ec2:CreateLaunchTemplate", "ec2:CreateFleet",
          "ec2:DescribeSpotPriceHistory", "pricing:GetProducts", "ec2:TerminateInstances",
          "ec2:DescribeInstanceStatus", "iam:GetInstanceProfile", "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile", "eks:DescribeCluster"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.karpenter_node.arn
      }
    ]
  })
}

resource "aws_iam_role" "karpenter_node" {
  name = "skills-sqs-karpenter-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_eks_access_entry" "karpenter_node" {
  provider      = aws.oregon
  cluster_name  = aws_eks_cluster.sqs.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

resource "aws_iam_role" "keda_operator" {
  name = "skills-sqs-keda-operator-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:keda:keda-operator"
        }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "keda_operator" {
  name = "inline"
  role = aws_iam_role.keda_operator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ListQueues",
        "cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "sqs_worker" {
  name = "skills-sqs-worker-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:skills-sqs:sqs-worker-sa"
        }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "sqs_worker" {
  name = "inline"
  role = aws_iam_role.sqs_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage", "sqs:DeleteMessage",
        "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"
      ]
      Resource = aws_sqs_queue.skills.arn
    }]
  })
}

resource "aws_ecr_repository" "worker" {
  provider             = aws.oregon
  name                 = "skills-sqs-worker"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = local.common_tags
}

resource "null_resource" "worker_image" {
  triggers = {
    src = filemd5("${path.module}/모듈4_지급파일/worker.py")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      REGION=us-west-2
      REPO='${aws_ecr_repository.worker.repository_url}'
      ACCOUNT='${local.account_id}'
      DIR=$(mktemp -d)
      mkdir -p "$DIR/layer/app"
      cp "${path.module}/모듈4_지급파일/worker.py" "$DIR/layer/app/"
      python3 -m pip install --quiet --disable-pip-version-check --root-user-action=ignore --target "$DIR/layer/app" boto3
      tar -cf "$DIR/layer.tar" -C "$DIR/layer" app
      if ! command -v crane >/dev/null 2>&1; then
        curl -fsSL -o /tmp/crane.tgz https://github.com/google/go-containerregistry/releases/download/v0.20.2/go-containerregistry_Linux_x86_64.tar.gz
        tar xzf /tmp/crane.tgz --no-same-owner -C /tmp crane
        install -m 0755 /tmp/crane /usr/local/bin/crane
      fi
      aws ecr get-login-password --region "$REGION" | crane auth login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
      crane mutate public.ecr.aws/docker/library/python:3.12-slim \
        --append "$DIR/layer.tar" \
        --entrypoint /usr/local/bin/python \
        --cmd '-u,/app/worker.py' \
        --env PYTHONPATH=/app \
        -t "$REPO:latest"
    EOT
  }

  depends_on = [aws_ecr_repository.worker]
}
