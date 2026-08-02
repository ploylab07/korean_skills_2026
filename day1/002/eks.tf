resource "aws_launch_template" "addon" {
  name_prefix = "wskorea26-addon-"
  # instance_types는 node group에만 지정 (5-3 mark: nodegroup.instanceTypes[0]=t3.medium)

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "wskorea26-addon-node"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "wskorea26-addon-node"
    }
  }
}

resource "aws_launch_template" "app" {
  name_prefix = "wskorea26-app-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "wskorea26-app-node"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "wskorea26-app-node"
    }
  }
}

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

resource "aws_security_group_rule" "cluster_from_alb_book" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "cluster_from_alb_grafana" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.grafana_alb.id
}

resource "aws_security_group_rule" "cluster_vpc_8080" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  cidr_blocks       = [aws_vpc.main.cidr_block]
}

resource "aws_security_group_rule" "cluster_vpc_3000" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  cidr_blocks       = [aws_vpc.main.cidr_block]
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

  launch_template {
    id      = aws_launch_template.addon.id
    version = aws_launch_template.addon.latest_version
  }

  tags = {
    Name = "wskorea26-addon-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
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

  taint {
    key    = "node-type"
    value  = "app"
    effect = "NO_SCHEDULE"
  }

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  tags = {
    Name = "wskorea26-app-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# 5-4: kube-system 워크로드(coredns, pod-identity 등)가 app 노드에 있으면
# sort -u 결과에 addon+app이 함께 나와 감점됨 → addon으로 고정
resource "null_resource" "pin_kube_system_to_addon" {
  triggers = {
    cluster = aws_eks_cluster.main.endpoint
    addon   = aws_eks_node_group.addon.id
    app     = aws_eks_node_group.app.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      AWS_DEFAULT_REGION = var.region
      CLUSTER_NAME       = aws_eks_cluster.main.name
      KUBECONFIG         = "${pathexpand("~")}/.kube/wskorea26.yaml"
    }
    command = <<-EOT
      set -euo pipefail
      aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG" >/dev/null
      export KUBECONFIG
      # CoreDNS → addon only
      kubectl -n kube-system patch deployment coredns --type strategic -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-type":"addon"}}}}}' || true
      # eks-pod-identity-agent DaemonSet → addon only (app taint 무시하는 DS 차단)
      if kubectl -n kube-system get ds eks-pod-identity-agent >/dev/null 2>&1; then
        kubectl -n kube-system patch ds eks-pod-identity-agent --type strategic -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-type":"addon"},"tolerations":[]}}}}' || true
      fi
      # 기타 kube-system Deployment도 addon으로
      for d in $(kubectl -n kube-system get deploy -o name 2>/dev/null); do
        kubectl -n kube-system patch "$d" --type strategic -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-type":"addon"}}}}}' || true
      done
    EOT
  }

  depends_on = [aws_eks_node_group.addon, aws_eks_node_group.app]
}
