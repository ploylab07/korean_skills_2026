resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.35"

  vpc_config {
    subnet_ids              = [aws_subnet.priv_c.id, aws_subnet.priv_d.id]
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_controller,
  ]

  tags = { Name = local.cluster_name }
}

resource "aws_eks_node_group" "addon" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "wskorea26-addon-ng"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [aws_subnet.priv_c.id, aws_subnet.priv_d.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  labels = {
    "node-type" = "addon"
  }

  tags = {
    Name = "wskorea26-addon-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "wskorea26-app-ng"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [aws_subnet.priv_c.id, aws_subnet.priv_d.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  labels = {
    "node-type" = "app"
  }

  tags = {
    Name = "wskorea26-app-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}
