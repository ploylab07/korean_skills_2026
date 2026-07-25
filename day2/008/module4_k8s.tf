############################################
# Module 4 — Helm / K8s (CLI; plan-safe)
############################################

resource "local_file" "k8s_workloads" {
  filename = "${path.module}/.generated/workloads.yaml"
  content = templatefile("${path.module}/files/workloads.yaml.tftpl", {
    node_role_name  = aws_iam_role.karpenter_node.name
    worker_role_arn = aws_iam_role.sqs_worker.arn
    worker_image    = "${aws_ecr_repository.worker.repository_url}:latest"
    queue_url       = aws_sqs_queue.skills.url
  })
}

resource "null_resource" "k8s_stack" {
  triggers = {
    cluster = aws_eks_cluster.sqs.name
    yaml    = local_file.k8s_workloads.content
    img     = null_resource.worker_image.id
    keda    = var.keda_version
    karp    = var.karpenter_version
  }

  depends_on = [
    aws_eks_cluster.sqs,
    aws_eks_fargate_profile.keda,
    aws_eks_fargate_profile.karpenter,
    aws_eks_fargate_profile.coredns,
    aws_eks_access_entry.karpenter_node,
    aws_ec2_tag.cluster_sg_discovery,
    null_resource.worker_image,
    aws_iam_role_policy.karpenter_controller,
    aws_iam_role_policy.keda_operator,
    aws_iam_role_policy.sqs_worker,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG=/tmp/skills-sqs-tf.kubeconfig
      aws eks update-kubeconfig --region us-west-2 --name ${aws_eks_cluster.sqs.name} --kubeconfig "$KUBECONFIG"

      # CoreDNS on Fargate
      kubectl -n kube-system rollout restart deployment coredns || true
      for i in $(seq 1 60); do
        kubectl -n kube-system get pods -l k8s-app=kube-dns --field-selector=status.phase=Running 2>/dev/null | grep -q Running && break
        sleep 10
      done

      # Karpenter
      helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
        --version ${var.karpenter_version} \
        --namespace karpenter --create-namespace \
        --set settings.clusterName=${aws_eks_cluster.sqs.name} \
        --set settings.interruptionQueue= \
        --set-json 'serviceAccount.annotations={"eks.amazonaws.com/role-arn":"${aws_iam_role.karpenter_controller.arn}"}' \
        --set controller.resources.requests.cpu=100m \
        --set controller.resources.requests.memory=256Mi \
        --wait --timeout 10m

      # KEDA
      helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
      helm repo update kedacore
      helm upgrade --install keda kedacore/keda \
        --version ${var.keda_version} \
        --namespace keda --create-namespace \
        --set-json 'serviceAccount.operator.annotations={"eks.amazonaws.com/role-arn":"${aws_iam_role.keda_operator.arn}"}' \
        --wait --timeout 10m

      kubectl -n karpenter annotate sa karpenter eks.amazonaws.com/role-arn=${aws_iam_role.karpenter_controller.arn} --overwrite || true
      kubectl -n keda annotate sa keda-operator eks.amazonaws.com/role-arn=${aws_iam_role.keda_operator.arn} --overwrite || true

      for i in $(seq 1 60); do
        kubectl get crd ec2nodeclasses.karpenter.k8s.aws scaledobjects.keda.sh >/dev/null 2>&1 && break
        sleep 5
      done

      kubectl apply -f ${local_file.k8s_workloads.filename}
    EOT
  }
}
