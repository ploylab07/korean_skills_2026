resource "aws_security_group" "eks_cluster" {
  name        = "wsc2026-eks-cluster-sg"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "wsc2026-eks-cluster-sg" })
}

resource "aws_security_group" "eks_nodes" {
  name        = "wsc2026-eks-nodes-sg"
  description = "EKS nodes security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "wsc2026-eks-nodes-sg" })
}

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = "1.35"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = [aws_subnet.app_a.id, aws_subnet.app_b.id]
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.keys["wsc2026-eks-kms"].arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]

  tags = merge(local.common_tags, { Name = local.cluster_name })
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_eks_node_group" "addon" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "wsc2026-addon-nodegroup"
  node_role_arn   = aws_iam_role.eks_addon_node.arn
  subnet_ids      = [aws_subnet.app_a.id, aws_subnet.app_b.id]

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  instance_types = ["t3.medium"]

  labels = {
    "wsc2026/node" = "addon"
  }

  tags = merge(local.common_tags, {
    Name = "wsc2026-addon-node"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_addon_node_worker,
    aws_iam_role_policy_attachment.eks_addon_node_cni,
    aws_iam_role_policy_attachment.eks_addon_node_ecr,
  ]
}

resource "aws_eks_node_group" "workload" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "wsc2026-workload-ng"
  node_role_arn   = aws_iam_role.eks_workload_node.arn
  subnet_ids      = [aws_subnet.app_a.id, aws_subnet.app_b.id]

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  instance_types = ["t3.medium"]

  labels = {
    "wsc2026/node" = "application"
  }

  taint {
    key    = "wsc2026/node"
    value  = "application"
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.common_tags, {
    Name = "wsc2026-workload-node"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_workload_node_worker,
    aws_iam_role_policy_attachment.eks_workload_node_cni,
    aws_iam_role_policy_attachment.eks_workload_node_ecr,
  ]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "eks_pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
}


resource "aws_iam_policy" "book_pod" {
  name = "wsc2026-book-pod-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"]
      Resource = aws_dynamodb_table.book.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "book_pod" {
  role       = aws_iam_role.book_pod.name
  policy_arn = aws_iam_policy.book_pod.arn
}
