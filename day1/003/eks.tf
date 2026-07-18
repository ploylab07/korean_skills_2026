resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.35"

  vpc_config {
    subnet_ids              = [aws_subnet.app_a.id, aws_subnet.app_b.id, aws_subnet.hub_a.id, aws_subnet.hub_b.id]
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  tags = {
    Name = local.cluster_name
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  depends_on   = [aws_eks_node_group.addon, aws_eks_node_group.workload]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  configuration_values = jsonencode({
    corefile = <<-EOF
      .:53 {
          errors
          health {
              lameduck 5s
            }
          ready
          kubernetes wsc2026.skills.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
          }
          prometheus :9153
          forward . /etc/resolv.conf
          cache 30
          loop
          reload
          loadbalance
      }
    EOF
  })

  depends_on = [aws_eks_node_group.addon, aws_eks_node_group.workload]
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
  depends_on   = [aws_eks_node_group.addon, aws_eks_node_group.workload]
}

resource "aws_eks_node_group" "addon" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "wsc2026-addon-nodegroup"
  node_role_arn   = aws_iam_role.eks_addon_node.arn
  subnet_ids      = [aws_subnet.app_a.id, aws_subnet.app_b.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  labels = {
    "wsc2026/node" = "addon"
  }

  tags = {
    Name = "wsc2026-addon-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.addon_worker,
    aws_iam_role_policy_attachment.addon_cni,
    aws_iam_role_policy_attachment.addon_ecr,
  ]
}

resource "aws_eks_node_group" "workload" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "wsc2026-workload-ng"
  node_role_arn   = aws_iam_role.eks_workload_node.arn
  subnet_ids      = [aws_subnet.app_a.id, aws_subnet.app_b.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  labels = {
    "wsc2026/node" = "application"
  }

  tags = {
    Name = "wsc2026-workload-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.workload_worker,
    aws_iam_role_policy_attachment.workload_cni,
    aws_iam_role_policy_attachment.workload_ecr,
  ]
}

resource "aws_eks_pod_identity_association" "book" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "wsc2026"
  service_account = "wsc2026-book-sa"
  role_arn        = aws_iam_role.book_pod.arn

  depends_on = [aws_eks_addon.pod_identity]
}
