############################################
# Module 4 — Observability (ap-northeast-1 / tokyo)
############################################

resource "aws_vpc" "m4" {
  provider             = aws.tokyo
  cidr_block           = "10.80.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "o11y-eks-vpc" })
}

resource "aws_internet_gateway" "m4" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.m4.id

  tags = merge(local.common_tags, { Name = "o11y-eks-igw" })
}

resource "aws_subnet" "m4_public_a" {
  provider                = aws.tokyo
  vpc_id                  = aws_vpc.m4.id
  cidr_block              = "10.80.0.0/24"
  availability_zone       = data.aws_availability_zones.tokyo.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                     = "o11y-eks-public-a"
    "kubernetes.io/role/elb"                 = "1"
    "kubernetes.io/cluster/o11y-cluster"     = "shared"
  })
}

resource "aws_subnet" "m4_public_b" {
  provider                = aws.tokyo
  vpc_id                  = aws_vpc.m4.id
  cidr_block              = "10.80.1.0/24"
  availability_zone       = data.aws_availability_zones.tokyo.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                     = "o11y-eks-public-b"
    "kubernetes.io/role/elb"                 = "1"
    "kubernetes.io/cluster/o11y-cluster"     = "shared"
  })
}

resource "aws_subnet" "m4_private_a" {
  provider          = aws.tokyo
  vpc_id            = aws_vpc.m4.id
  cidr_block        = "10.80.10.0/24"
  availability_zone = data.aws_availability_zones.tokyo.names[0]

  tags = merge(local.common_tags, {
    Name                                     = "o11y-eks-private-a"
    "kubernetes.io/role/internal-elb"        = "1"
    "kubernetes.io/cluster/o11y-cluster"     = "shared"
  })
}

resource "aws_subnet" "m4_private_b" {
  provider          = aws.tokyo
  vpc_id            = aws_vpc.m4.id
  cidr_block        = "10.80.11.0/24"
  availability_zone = data.aws_availability_zones.tokyo.names[1]

  tags = merge(local.common_tags, {
    Name                                     = "o11y-eks-private-b"
    "kubernetes.io/role/internal-elb"        = "1"
    "kubernetes.io/cluster/o11y-cluster"     = "shared"
  })
}

resource "aws_route_table" "m4_public" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.m4.id
  tags     = merge(local.common_tags, { Name = "o11y-eks-public-rt" })
}

resource "aws_route" "m4_public_default" {
  provider               = aws.tokyo
  route_table_id         = aws_route_table.m4_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.m4.id
}

resource "aws_route_table_association" "m4_public_a" {
  provider       = aws.tokyo
  subnet_id      = aws_subnet.m4_public_a.id
  route_table_id = aws_route_table.m4_public.id
}

resource "aws_route_table_association" "m4_public_b" {
  provider       = aws.tokyo
  subnet_id      = aws_subnet.m4_public_b.id
  route_table_id = aws_route_table.m4_public.id
}

resource "aws_eip" "m4_nat" {
  provider = aws.tokyo
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "o11y-eks-nat-eip" })
}

resource "aws_nat_gateway" "m4" {
  provider      = aws.tokyo
  allocation_id = aws_eip.m4_nat.id
  subnet_id     = aws_subnet.m4_public_a.id
  tags          = merge(local.common_tags, { Name = "o11y-eks-nat" })
  depends_on    = [aws_internet_gateway.m4]
}

resource "aws_route_table" "m4_private" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.m4.id
  tags     = merge(local.common_tags, { Name = "o11y-eks-private-rt" })
}

resource "aws_route" "m4_private_default" {
  provider               = aws.tokyo
  route_table_id         = aws_route_table.m4_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.m4.id
}

resource "aws_route_table_association" "m4_private_a" {
  provider       = aws.tokyo
  subnet_id      = aws_subnet.m4_private_a.id
  route_table_id = aws_route_table.m4_private.id
}

resource "aws_route_table_association" "m4_private_b" {
  provider       = aws.tokyo
  subnet_id      = aws_subnet.m4_private_b.id
  route_table_id = aws_route_table.m4_private.id
}

############################################
# EKS cluster
############################################

resource "aws_iam_role" "o11y_cluster" {
  provider = aws.tokyo
  name     = "o11y-eks-cluster-role"

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

resource "aws_iam_role_policy_attachment" "o11y_cluster" {
  provider   = aws.tokyo
  role       = aws_iam_role.o11y_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_security_group" "o11y_cluster" {
  provider = aws.tokyo
  name     = "o11y-eks-cluster-sg"
  vpc_id   = aws_vpc.m4.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_eks_cluster" "o11y" {
  provider = aws.tokyo
  name     = "o11y-cluster"
  role_arn = aws_iam_role.o11y_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids = [
      aws_subnet.m4_public_a.id, aws_subnet.m4_public_b.id,
      aws_subnet.m4_private_a.id, aws_subnet.m4_private_b.id,
    ]
    security_group_ids      = [aws_security_group.o11y_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.o11y_cluster]

  tags = local.common_tags
}

data "tls_certificate" "o11y_eks_oidc" {
  url = aws_eks_cluster.o11y.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "o11y_eks" {
  provider        = aws.tokyo
  url             = aws_eks_cluster.o11y.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.o11y_eks_oidc.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

############################################
# Node group — timezone Asia/Seoul via launch template
############################################

resource "aws_iam_role" "o11y_node" {
  provider = aws.tokyo
  name     = "o11y-node-role"

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

resource "aws_iam_role_policy_attachment" "m4_node_worker" {
  provider   = aws.tokyo
  role       = aws_iam_role.o11y_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "m4_node_cni" {
  provider   = aws.tokyo
  role       = aws_iam_role.o11y_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "m4_node_ecr" {
  provider   = aws.tokyo
  role       = aws_iam_role.o11y_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "m4_node_ssm" {
  provider   = aws.tokyo
  role       = aws_iam_role.o11y_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

locals {
  m4_timezone_userdata = <<-EOT
    Content-Type: multipart/mixed; boundary="==BOUNDARY=="
    MIME-Version: 1.0

    --==BOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    timedatectl set-timezone Asia/Seoul

    --==BOUNDARY==--
  EOT
}

resource "aws_launch_template" "o11y_ng" {
  provider  = aws.tokyo
  name      = "o11y-ng-lt"
  user_data = base64encode(local.m4_timezone_userdata)

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "o11y-node-group-node"
    })
  }

  tags = local.common_tags
}

resource "aws_eks_node_group" "o11y" {
  provider        = aws.tokyo
  cluster_name    = aws_eks_cluster.o11y.name
  node_group_name = "o11y-node-group"
  node_role_arn   = aws_iam_role.o11y_node.arn
  subnet_ids      = [aws_subnet.m4_private_a.id, aws_subnet.m4_private_b.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 2
  }

  launch_template {
    id      = aws_launch_template.o11y_ng.id
    version = "$Latest"
  }

  depends_on = [
    aws_iam_role_policy_attachment.m4_node_worker,
    aws_iam_role_policy_attachment.m4_node_cni,
    aws_iam_role_policy_attachment.m4_node_ecr,
    aws_iam_role_policy_attachment.m4_node_ssm,
    aws_nat_gateway.m4,
  ]

  tags = local.common_tags
}

############################################
# EKS Addons
############################################

resource "aws_eks_addon" "o11y_vpc_cni" {
  provider                    = aws.tokyo
  cluster_name                = aws_eks_cluster.o11y.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = local.common_tags
}

resource "aws_eks_addon" "o11y_kube_proxy" {
  provider                    = aws.tokyo
  cluster_name                = aws_eks_cluster.o11y.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.o11y]
  tags                        = local.common_tags
}

resource "aws_eks_addon" "o11y_coredns" {
  provider                    = aws.tokyo
  cluster_name                = aws_eks_cluster.o11y.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.o11y]
  tags                        = local.common_tags
}

resource "aws_eks_addon" "o11y_pod_identity" {
  provider                    = aws.tokyo
  cluster_name                = aws_eks_cluster.o11y.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.o11y]
  tags                        = local.common_tags
}

resource "aws_iam_role" "m4_ebs_csi" {
  provider = aws.tokyo
  name     = "o11y-ebs-csi-role"

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

resource "aws_iam_role_policy_attachment" "m4_ebs_csi" {
  provider   = aws.tokyo
  role       = aws_iam_role.m4_ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "m4_ebs_csi" {
  provider        = aws.tokyo
  cluster_name    = aws_eks_cluster.o11y.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.m4_ebs_csi.arn
  depends_on      = [aws_eks_addon.o11y_pod_identity]
}

resource "aws_eks_addon" "o11y_ebs_csi" {
  provider                    = aws.tokyo
  cluster_name                = aws_eks_cluster.o11y.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.o11y, aws_eks_addon.o11y_pod_identity, aws_eks_pod_identity_association.m4_ebs_csi]
  tags                        = local.common_tags
}

############################################
# ECR + image build — log-generator
############################################

resource "aws_ecr_repository" "log_generator" {
  provider             = aws.tokyo
  name                 = "o11y-log-generator"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = local.common_tags
}

resource "null_resource" "log_generator_image" {
  triggers = {
    app_hash        = filemd5("${path.module}/Module4-Container-Logging/app.py")
    dockerfile_hash = filemd5("${path.module}/Module4-Container-Logging/Dockerfile")
    repo_url        = aws_ecr_repository.log_generator.repository_url
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.ap-northeast-1.amazonaws.com
      docker build -t ${aws_ecr_repository.log_generator.repository_url}:latest ${path.module}/Module4-Container-Logging
      docker push ${aws_ecr_repository.log_generator.repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.log_generator]
}

############################################
# IAM — AWS Load Balancer Controller (IRSA)
############################################

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.o11y_eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.o11y_eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.o11y_eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  provider           = aws.tokyo
  name               = "o11y-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "alb_controller" {
  provider = aws.tokyo
  name     = "o11y-alb-controller-policy"
  role     = aws_iam_role.alb_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DeleteSecurityGroup",
          "elasticloadbalancing:*",
          "iam:CreateServiceLinkedRole",
          "iam:GetServerCertificate",
          "iam:ListServerCertificates",
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:DescribeProtection",
          "shield:GetSubscriptionState",
          "shield:DescribeSubscription",
          "shield:CreateProtection",
          "shield:DeleteProtection",
        ]
        Resource = "*"
      },
    ]
  })
}

############################################
# ALBs + Target Groups (explicit)
############################################

resource "aws_security_group" "o11y_alb" {
  provider = aws.tokyo
  name     = "o11y-alb-sg"
  vpc_id   = aws_vpc.m4.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_security_group_rule" "nodes_from_alb_app" {
  provider                 = aws.tokyo
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.o11y.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.o11y_alb.id
}

resource "aws_security_group_rule" "nodes_from_alb_grafana" {
  provider                 = aws.tokyo
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.o11y.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.o11y_alb.id
}

resource "aws_lb" "o11y_app" {
  provider           = aws.tokyo
  name               = "o11y-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.o11y_alb.id]
  subnets            = [aws_subnet.m4_public_a.id, aws_subnet.m4_public_b.id]

  tags = local.common_tags
}

resource "aws_lb_target_group" "o11y_app" {
  provider    = aws.tokyo
  name        = "o11y-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.m4.id
  target_type = "ip"

  health_check {
    path                = "/healthz"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "o11y_app" {
  provider          = aws.tokyo
  load_balancer_arn = aws_lb.o11y_app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.o11y_app.arn
  }
}

resource "aws_lb" "o11y_grafana" {
  provider           = aws.tokyo
  name               = "o11y-grafana-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.o11y_alb.id]
  subnets            = [aws_subnet.m4_public_a.id, aws_subnet.m4_public_b.id]

  tags = local.common_tags
}

resource "aws_lb_target_group" "o11y_grafana" {
  provider    = aws.tokyo
  name        = "o11y-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.m4.id
  target_type = "ip"

  health_check {
    path                = "/api/health"
    port                = "3000"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "o11y_grafana" {
  provider          = aws.tokyo
  load_balancer_arn = aws_lb.o11y_grafana.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.o11y_grafana.arn
  }
}
