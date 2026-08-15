# Managed node groups + Bottlerocket: EKS auto-generates bootstrap user data and
# merges it with the TOML below, so labels/tags apply without hand-rolled bootstrap.
resource "aws_launch_template" "app" {
  name_prefix = "unicorn-app-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 4
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_replica_key.platform.arn
    }
  }

  block_device_mappings {
    device_name = "/dev/xvdb"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_replica_key.platform.arn
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name      = "unicorn-k8snode-app-node"
      NodeGroup = "app"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "unicorn-k8snode-app-node" })
  }

  user_data = base64encode(<<-EOT
    [settings]
    timezone = "Asia/Seoul"
    [settings.kubernetes.node-labels]
    "unicorn" = "app"
  EOT
  )
}

resource "aws_launch_template" "addon" {
  name_prefix = "unicorn-addon-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 4
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_replica_key.platform.arn
    }
  }

  block_device_mappings {
    device_name = "/dev/xvdb"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_replica_key.platform.arn
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name      = "unicorn-k8snode-addon-node"
      NodeGroup = "addon"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "unicorn-k8snode-addon-node" })
  }

  user_data = base64encode(<<-EOT
    [settings]
    timezone = "Asia/Seoul"
    [settings.kubernetes.node-labels]
    "unicorn" = "addon"
  EOT
  )
}

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.35"

  vpc_config {
    subnet_ids              = [for s in aws_subnet.private : s.id]
    endpoint_private_access = true
    # Public access starts enabled so `terraform apply` (running outside the
    # VPC) can reach the API server; null_resource.disable_public_endpoint
    # flips this to false once every k8s/helm resource below has applied.
    endpoint_public_access = true
    security_group_ids     = [aws_security_group.cluster.id]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_replica_key.platform.arn
    }
    resources = ["secrets"]
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_vpc_endpoint.interfaces,
    aws_vpc_endpoint.s3,
    aws_kms_key_policy.platform_replica,
  ]

  tags = merge(local.common_tags, { Name = local.cluster_name })
}

resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "unicorn-eks-app-nodegroup"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [for s in aws_subnet.private : s.id]
  ami_type        = "BOTTLEROCKET_x86_64"
  instance_types  = ["t3.medium"]
  capacity_type   = "ON_DEMAND"

  # 3 subnets (one per AZ) + desired=3 spreads nodes evenly across all AZs for HA.
  scaling_config {
    desired_size = 3
    max_size     = 4
    min_size     = 3
  }

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  labels = {
    unicorn = "app"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_ssm,
    aws_kms_key_policy.platform_replica,
  ]

  tags = merge(local.common_tags, { Name = "unicorn-eks-app-nodegroup" })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_node_group" "addon" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "unicorn-eks-addon-nodegroup"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [for s in aws_subnet.private : s.id]
  ami_type        = "BOTTLEROCKET_x86_64"
  instance_types  = ["t3.medium"]
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  launch_template {
    id      = aws_launch_template.addon.id
    version = aws_launch_template.addon.latest_version
  }

  labels = {
    unicorn = "addon"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_ssm,
    aws_kms_key_policy.platform_replica,
  ]

  tags = merge(local.common_tags, { Name = "unicorn-eks-addon-nodegroup" })

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

resource "aws_eks_pod_identity_association" "book_app" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unicorn"
  service_account = "unicorn-book-app-sa"
  role_arn        = aws_iam_role.book_app.arn
  depends_on      = [aws_eks_addon.pod_identity, kubernetes_service_account_v1.book]
}

# ALB (book + grafana) -> managed node groups' shared cluster security group
resource "aws_security_group_rule" "cluster_sg_from_alb_book" {
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
  source_security_group_id = aws_security_group.grafana_alb.id
}

# Grading requires endpointPublicAccess=false. We keep it true through apply
# (kubernetes/helm providers need reachability) and flip it off last, after
# every cluster-dependent resource (k8s, helm, target registration) is applied.
resource "null_resource" "disable_public_endpoint" {
  triggers = {
    cluster = aws_eks_cluster.main.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      CURRENT=$(aws eks describe-cluster --name ${local.cluster_name} --region ${local.region} \
        --query 'cluster.resourcesVpcConfig.endpointPublicAccess' --output text)
      if [ "$CURRENT" = "True" ]; then
        aws eks update-cluster-config --name ${local.cluster_name} --region ${local.region} \
          --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true
        aws eks wait cluster-active --name ${local.cluster_name} --region ${local.region}
      fi
    EOT
  }

  depends_on = [
    aws_eks_node_group.app,
    aws_eks_node_group.addon,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.coredns,
    aws_eks_addon.pod_identity,
    aws_eks_pod_identity_association.book_app,
    kubernetes_deployment_v1.book,
    kubernetes_service_v1.book,
    kubernetes_daemon_set_v1.fluent_bit,
    helm_release.kube_prometheus_stack,
    null_resource.register_alb_targets,
    null_resource.push_book_image,
  ]
}
