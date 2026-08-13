# Managed NG + Bottlerocket: EKS injects bootstrap; LT only for SG/tags/extra labels
resource "aws_launch_template" "addon" {
  name_prefix = "gj2026-addon-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name      = "gj2026-addon-node"
      NodeGroup = "addon"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "gj2026-addon-node" })
  }

  # BR 1.63+: hostname-override-source is only private-dns-name|instance-id
  # Use instance-id so pluto does not force private DNS; bootstrap then sets full name.
  user_data = base64encode(<<-EOT
settings.kubernetes.hostname-override-source = "instance-id"
settings.kubernetes.node-labels.role = "addon"
settings.kubernetes.node-labels.gj2026 = "addon"
settings.bootstrap-containers.hostname.source = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/hostname-bootstrap:latest"
settings.bootstrap-containers.hostname.mode = "always"
settings.bootstrap-containers.hostname.essential = true
settings.bootstrap-containers.hostname.user-data = "${base64encode("addon")}"
  EOT
  )
}

resource "aws_launch_template" "app" {
  name_prefix = "gj2026-app-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name      = "gj2026-app-node"
      NodeGroup = "app"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "gj2026-app-node" })
  }

  user_data = base64encode(<<-EOT
settings.kubernetes.hostname-override-source = "instance-id"
settings.kubernetes.node-labels.role = "app"
settings.kubernetes.node-labels.gj2026 = "app"
settings.bootstrap-containers.hostname.source = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/hostname-bootstrap:latest"
settings.bootstrap-containers.hostname.mode = "always"
settings.bootstrap-containers.hostname.essential = true
settings.bootstrap-containers.hostname.user-data = "${base64encode("app")}"
  EOT
  )
}

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.35"

  vpc_config {
    subnet_ids              = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.cluster.id]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_vpc_endpoint.interfaces,
    aws_vpc_endpoint.s3,
  ]

  tags = merge(local.common_tags, { Name = local.cluster_name })
}

resource "aws_eks_node_group" "addon" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "gj2026-eks-addon-nodegroup"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  ami_type        = "BOTTLEROCKET_x86_64"
  instance_types  = ["t3.medium"]
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  launch_template {
    id      = aws_launch_template.addon.id
    version = aws_launch_template.addon.latest_version
  }

  labels = {
    role   = "addon"
    gj2026 = "addon"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  tags = merge(local.common_tags, { Name = "gj2026-eks-addon-nodegroup" })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "gj2026-eks-app-nodegroup"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  ami_type        = "BOTTLEROCKET_x86_64"
  instance_types  = ["m5.large"]
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  labels = {
    role   = "app"
    gj2026 = "app"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  tags = merge(local.common_tags, { Name = "gj2026-eks-app-nodegroup" })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.addon, aws_eks_node_group.app]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.addon]
}

# Pod Identity intentionally omitted — book uses node instance role via IMDS

# Managed node groups use the cluster primary SG; allow ALB health/traffic
resource "aws_security_group_rule" "cluster_sg_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "cluster_sg_from_alb_grafana" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
}

# Custom Bottlerocket hostnames need username != system:node:<iid>
# so NodeRestriction does not block gj2026.<iid>.{addon|app}.node registration.
resource "aws_eks_access_entry" "nodes" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.eks_node.arn
  type              = "STANDARD"
  user_name         = "gj2026-worker"
  kubernetes_groups = []
}

resource "aws_eks_access_policy_association" "nodes_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.eks_node.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.nodes]
}

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapRoles = yamlencode([{
      rolearn  = aws_iam_role.eks_node.arn
      username = "gj2026-worker"
      groups   = ["system:bootstrappers", "system:nodes", "system:masters"]
    }])
  }
  force = true
  depends_on = [aws_eks_cluster.main, aws_eks_node_group.addon]
}
