############################################
# Module 4 — Helm / K8s workloads
# kubernetes_manifest는 클러스터 미존재 시 plan 실패 → kubectl local-exec 사용
############################################

resource "null_resource" "kubeconfig" {
  depends_on = [aws_eks_cluster.sqs]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region us-west-2 --name ${aws_eks_cluster.sqs.name} --kubeconfig /tmp/skills-sqs-tf.kubeconfig
    EOT
  }
}

resource "null_resource" "coredns_restart" {
  depends_on = [aws_eks_fargate_profile.coredns, null_resource.kubeconfig]
  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=/tmp/skills-sqs-tf.kubeconfig
      kubectl -n kube-system rollout restart deployment coredns || true
      kubectl -n kube-system rollout status deployment coredns --timeout=300s || true
    EOT
  }
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  namespace        = "karpenter"
  create_namespace = true
  wait             = true
  timeout          = 600

  set {
    name  = "settings.clusterName"
    value = aws_eks_cluster.sqs.name
  }
  set {
    name  = "settings.interruptionQueue"
    value = ""
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }
  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  depends_on = [
    aws_eks_fargate_profile.karpenter,
    null_resource.coredns_restart,
    aws_iam_role_policy.karpenter_controller,
    null_resource.kubeconfig,
  ]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_version
  namespace        = "keda"
  create_namespace = true
  wait             = true
  timeout          = 600

  set {
    name  = "serviceAccount.operator.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.keda_operator.arn
  }

  depends_on = [
    aws_eks_fargate_profile.keda,
    null_resource.coredns_restart,
    aws_iam_role_policy.keda_operator,
    null_resource.kubeconfig,
  ]
}

resource "local_file" "k8s_workloads" {
  filename = "${path.module}/.generated/workloads.yaml"
  content = templatefile("${path.module}/files/workloads.yaml.tftpl", {
    node_role_name = aws_iam_role.karpenter_node.name
    worker_role_arn = aws_iam_role.sqs_worker.arn
    worker_image    = "${aws_ecr_repository.worker.repository_url}:latest"
    queue_url       = aws_sqs_queue.skills.url
  })
}

resource "null_resource" "k8s_workloads" {
  triggers = {
    yaml = local_file.k8s_workloads.content
    img  = null_resource.worker_image.id
  }

  depends_on = [
    helm_release.karpenter,
    helm_release.keda,
    null_resource.worker_image,
    aws_eks_access_entry.karpenter_node,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG=/tmp/skills-sqs-tf.kubeconfig
      aws eks update-kubeconfig --region us-west-2 --name ${aws_eks_cluster.sqs.name} --kubeconfig "$KUBECONFIG"
      # wait CRDs
      for i in $(seq 1 60); do
        kubectl get crd ec2nodeclasses.karpenter.k8s.aws scaledobjects.keda.sh >/dev/null 2>&1 && break
        sleep 5
      done
      kubectl apply -f ${local_file.k8s_workloads.filename}
      kubectl -n keda annotate sa keda-operator eks.amazonaws.com/role-arn=${aws_iam_role.keda_operator.arn} --overwrite || true
      kubectl -n karpenter annotate sa karpenter eks.amazonaws.com/role-arn=${aws_iam_role.karpenter_controller.arn} --overwrite || true
    EOT
  }
}
