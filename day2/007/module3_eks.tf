############################################
# Module 3 — EKS Scaling (ap-northeast-2 / seoul)
############################################

resource "aws_vpc" "m3" {
  provider             = aws.seoul
  cidr_block           = "10.70.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "skm-eks-vpc" })
}

resource "aws_internet_gateway" "m3" {
  provider = aws.seoul
  vpc_id   = aws_vpc.m3.id

  tags = merge(local.common_tags, { Name = "skm-eks-igw" })
}

resource "aws_subnet" "m3_public_a" {
  provider                = aws.seoul
  vpc_id                  = aws_vpc.m3.id
  cidr_block              = "10.70.0.0/24"
  availability_zone       = data.aws_availability_zones.seoul.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                    = "skm-eks-public-a"
    "kubernetes.io/role/elb"                = "1"
    "karpenter.sh/discovery"                = "skm-eks-cluster"
    "kubernetes.io/cluster/skm-eks-cluster" = "shared"
  })
}

resource "aws_subnet" "m3_public_b" {
  provider                = aws.seoul
  vpc_id                  = aws_vpc.m3.id
  cidr_block              = "10.70.1.0/24"
  availability_zone       = data.aws_availability_zones.seoul.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                    = "skm-eks-public-b"
    "kubernetes.io/role/elb"                = "1"
    "karpenter.sh/discovery"                = "skm-eks-cluster"
    "kubernetes.io/cluster/skm-eks-cluster" = "shared"
  })
}

resource "aws_route_table" "m3_public" {
  provider = aws.seoul
  vpc_id   = aws_vpc.m3.id
  tags     = merge(local.common_tags, { Name = "skm-eks-public-rt" })
}

resource "aws_route" "m3_public_default" {
  provider               = aws.seoul
  route_table_id         = aws_route_table.m3_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.m3.id
}

resource "aws_route_table_association" "m3_public_a" {
  provider       = aws.seoul
  subnet_id      = aws_subnet.m3_public_a.id
  route_table_id = aws_route_table.m3_public.id
}

resource "aws_route_table_association" "m3_public_b" {
  provider       = aws.seoul
  subnet_id      = aws_subnet.m3_public_b.id
  route_table_id = aws_route_table.m3_public.id
}

############################################
# SQS
############################################

resource "aws_sqs_queue" "order" {
  provider = aws.seoul
  name     = "skm-order-queue"
  tags     = local.common_tags
}

############################################
# EKS cluster
############################################

resource "aws_iam_role" "skm_cluster" {
  provider = aws.seoul
  name     = "skm-eks-cluster-role"

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

resource "aws_iam_role_policy_attachment" "skm_cluster" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_security_group" "skm_cluster" {
  provider = aws.seoul
  name     = "skm-eks-cluster-sg"
  vpc_id   = aws_vpc.m3.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_ec2_tag" "skm_cluster_sg_discovery" {
  provider    = aws.seoul
  # Must tag the EKS-managed cluster SG (not the extra additional SG),
  # otherwise Karpenter nodes cannot reach the API server / join the cluster.
  resource_id = aws_eks_cluster.skm.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = "skm-eks-cluster"
}

resource "aws_eks_cluster" "skm" {
  provider = aws.seoul
  name     = "skm-eks-cluster"
  role_arn = aws_iam_role.skm_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids              = [aws_subnet.m3_public_a.id, aws_subnet.m3_public_b.id]
    security_group_ids       = [aws_security_group.skm_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.skm_cluster]

  tags = local.common_tags
}

data "tls_certificate" "skm_eks_oidc" {
  url = aws_eks_cluster.skm.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "skm_eks" {
  provider        = aws.seoul
  url             = aws_eks_cluster.skm.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.skm_eks_oidc.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

############################################
# Managed node group — cluster addon nodes
############################################

resource "aws_iam_role" "skm_addon_node" {
  provider = aws.seoul
  name     = "skm-addon-node-role"

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

resource "aws_iam_role_policy_attachment" "m3_node_worker" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_addon_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "m3_node_cni" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_addon_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "m3_node_ecr" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_addon_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "m3_node_ssm" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_addon_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_launch_template" "skm_addon_ng" {
  provider = aws.seoul
  name     = "skm-cluster-addon-ng-lt"

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "skm-cluster-addon-ng-node"
    })
  }

  tags = local.common_tags
}

resource "aws_eks_node_group" "addon" {
  provider        = aws.seoul
  cluster_name    = aws_eks_cluster.skm.name
  node_group_name = "skm-cluster-addon-ng"
  node_role_arn   = aws_iam_role.skm_addon_node.arn
  subnet_ids      = [aws_subnet.m3_public_a.id, aws_subnet.m3_public_b.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    min_size     = 1
    desired_size = 1
    max_size     = 1
  }

  launch_template {
    id      = aws_launch_template.skm_addon_ng.id
    version = "$Latest"
  }

  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    "skm/role" = "addon"
  }

  depends_on = [
    aws_iam_role_policy_attachment.m3_node_worker,
    aws_iam_role_policy_attachment.m3_node_cni,
    aws_iam_role_policy_attachment.m3_node_ecr,
    aws_iam_role_policy_attachment.m3_node_ssm,
  ]

  tags = local.common_tags
}

############################################
# EKS Addons
############################################

resource "aws_eks_addon" "skm_vpc_cni" {
  provider                    = aws.seoul
  cluster_name                = aws_eks_cluster.skm.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = local.common_tags
}

resource "aws_eks_addon" "skm_kube_proxy" {
  provider                    = aws.seoul
  cluster_name                = aws_eks_cluster.skm.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.addon]
  tags                        = local.common_tags
}

resource "aws_eks_addon" "skm_coredns" {
  provider                    = aws.seoul
  cluster_name                = aws_eks_cluster.skm.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.addon]
  tags                        = local.common_tags
}

resource "aws_eks_addon" "skm_pod_identity" {
  provider                    = aws.seoul
  cluster_name                = aws_eks_cluster.skm.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.addon]
  tags                        = local.common_tags
}

resource "aws_iam_role" "skm_ebs_csi" {
  provider = aws.seoul
  name     = "skm-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "skm_ebs_csi" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "skm_ebs_csi" {
  provider        = aws.seoul
  cluster_name    = aws_eks_cluster.skm.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.skm_ebs_csi.arn
  depends_on      = [aws_eks_addon.skm_pod_identity]
}

resource "aws_eks_addon" "skm_ebs_csi" {
  provider                    = aws.seoul
  cluster_name                = aws_eks_cluster.skm.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.addon, aws_eks_addon.skm_pod_identity, aws_eks_pod_identity_association.skm_ebs_csi]
  tags                        = local.common_tags
}

############################################
# ECR + image build — order-processor
############################################

resource "aws_ecr_repository" "order_processor" {
  provider             = aws.seoul
  name                 = "skm-order-processor"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = local.common_tags
}

resource "null_resource" "order_processor_image" {
  triggers = {
    app_hash        = filemd5("${path.module}/Module3-EKS-Scaling/app.py")
    dockerfile_hash = filemd5("${path.module}/Module3-EKS-Scaling/Dockerfile")
    repo_url        = aws_ecr_repository.order_processor.repository_url
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.ap-northeast-2.amazonaws.com
      docker build -t ${aws_ecr_repository.order_processor.repository_url}:latest ${path.module}/Module3-EKS-Scaling
      docker push ${aws_ecr_repository.order_processor.repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.order_processor]
}

############################################
# IAM — Karpenter controller (IRSA)
############################################

data "aws_iam_policy_document" "skm_karpenter_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.skm_eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.skm_eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.skm_eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "skm_karpenter_controller" {
  provider           = aws.seoul
  name               = "skm-karpenter-controller-role"
  assume_role_policy = data.aws_iam_policy_document.skm_karpenter_controller_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "skm_karpenter_controller" {
  provider = aws.seoul
  name     = "skm-karpenter-controller-policy"
  role     = aws_iam_role.skm_karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts",
          "ssm:GetParameter",
          "iam:PassRole",
          "iam:CreateInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "eks:DescribeCluster",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
        ]
        Resource = "*"
      },
    ]
  })
}

############################################
# IAM — Karpenter node role + access entry
############################################

resource "aws_iam_role" "skm_karpenter_node" {
  provider = aws.seoul
  name     = "skm-karpenter-node-role"

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

resource "aws_iam_role_policy_attachment" "skm_karpenter_node_worker" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "skm_karpenter_node_cni" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "skm_karpenter_node_ecr" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "skm_karpenter_node_ssm" {
  provider   = aws.seoul
  role       = aws_iam_role.skm_karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "skm_karpenter_node" {
  provider = aws.seoul
  name     = "skm-karpenter-node-profile"
  role     = aws_iam_role.skm_karpenter_node.name
}

resource "aws_eks_access_entry" "skm_karpenter_node" {
  provider      = aws.seoul
  cluster_name  = aws_eks_cluster.skm.name
  principal_arn = aws_iam_role.skm_karpenter_node.arn
  type          = "EC2_LINUX"

  depends_on = [aws_eks_cluster.skm]
}

############################################
# Pod Identity — KEDA operator + order-processor app
############################################

resource "aws_iam_role" "skm_keda_operator" {
  provider = aws.seoul
  name     = "skm-keda-operator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "skm_keda_operator" {
  provider = aws.seoul
  name     = "skm-keda-operator-policy"
  role     = aws_iam_role.skm_keda_operator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage",
      ]
      Resource = [aws_sqs_queue.order.arn]
    }]
  })
}

resource "aws_eks_pod_identity_association" "skm_keda_operator" {
  provider        = aws.seoul
  cluster_name    = aws_eks_cluster.skm.name
  namespace       = "keda"
  service_account = "keda-operator"
  role_arn        = aws_iam_role.skm_keda_operator.arn
  depends_on      = [aws_eks_addon.skm_pod_identity]
}

resource "aws_iam_role" "skm_order_processor" {
  provider = aws.seoul
  name     = "skm-order-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "skm_order_processor" {
  provider = aws.seoul
  name     = "skm-order-processor-policy"
  role     = aws_iam_role.skm_order_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
      ]
      Resource = [aws_sqs_queue.order.arn]
    }]
  })
}

resource "aws_eks_pod_identity_association" "skm_order_processor" {
  provider        = aws.seoul
  cluster_name    = aws_eks_cluster.skm.name
  namespace       = "skillsmkt"
  service_account = "order-processor"
  role_arn        = aws_iam_role.skm_order_processor.arn
  depends_on      = [aws_eks_addon.skm_pod_identity]
}
