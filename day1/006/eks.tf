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
      Name      = "gj2026-eks-addon-node"
      NodeGroup = "addon"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "gj2026-eks-addon-node" })
  }

  # source=instance-id prevents PLUTO from overwriting hostname-override with private DNS.
  # Bootstrap then sets the full contest name gj2026.<iid>.addon.node before kubelet.
  user_data = base64encode(<<-EOT
settings.kubernetes.hostname-override-source = "instance-id"
settings.kubernetes.node-labels.role = "addon"
settings.kubernetes.node-labels.gj2026 = "addon"
settings.kubernetes.server-tls-bootstrap = true
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
      Name      = "gj2026-eks-app-node"
      NodeGroup = "app"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "gj2026-eks-app-node" })
  }

  user_data = base64encode(<<-EOT
settings.kubernetes.hostname-override-source = "instance-id"
settings.kubernetes.node-labels.role = "app"
settings.kubernetes.node-labels.gj2026 = "app"
settings.kubernetes.server-tls-bootstrap = true
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
    # Prefer CONFIG_MAP at first create so aws-auth owns node identity
    # (custom system:node:gj2026.{{SessionName}}.*). If the live cluster was
    # upgraded to API_AND_CONFIG_MAP for grader access entries, keep that value
    # here so terraform apply does not attempt an unsupported downgrade.
    # Never leave EC2_LINUX access entries on node roles — they override aws-auth.
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
  node_role_arn   = aws_iam_role.eks_addon_node.arn
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
    kubernetes_config_map_v1.aws_auth,
  ]

  tags = merge(local.common_tags, { Name = "gj2026-eks-addon-nodegroup" })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size, launch_template[0].version]
  }
}

resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "gj2026-eks-app-nodegroup"
  node_role_arn   = aws_iam_role.eks_app_node.arn
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
    kubernetes_config_map_v1.aws_auth,
  ]

  tags = merge(local.common_tags, { Name = "gj2026-eks-app-nodegroup" })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size, launch_template[0].version]
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

# Create aws-auth (CONFIG_MAP mode does not auto-create it).
# Username must equal CSR CN: system:node:gj2026.<iid>.{addon|app}.node
resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    # Keep YAML unquoted so plan matches live aws-auth (yamlencode adds quotes).
    mapRoles = <<-EOT
    - rolearn: ${aws_iam_role.eks_addon_node.arn}
      username: system:node:gj2026.{{SessionName}}.addon.node
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: ${aws_iam_role.eks_app_node.arn}
      username: system:node:gj2026.{{SessionName}}.app.node
      groups:
        - system:bootstrappers
        - system:nodes
    EOT
  }
  depends_on = [aws_eks_cluster.main]
}

# CONFIG_MAP clusters may omit this binding — without it nodes never join.
resource "kubernetes_cluster_role_v1" "eks_authenticator_aws_auth" {
  metadata {
    name = "eks-authenticator-aws-auth"
  }
  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["aws-auth"]
    verbs          = ["get", "watch", "list"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["list", "watch"]
  }
  depends_on = [aws_eks_cluster.main]
}

resource "kubernetes_cluster_role_binding_v1" "eks_authenticator_aws_auth" {
  metadata {
    name = "eks-authenticator-aws-auth"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.eks_authenticator_aws_auth.metadata[0].name
  }
  subject {
    kind      = "User"
    name      = "eks:authenticator"
    api_group = "rbac.authorization.k8s.io"
  }
}
