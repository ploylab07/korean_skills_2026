############################################
# Module 3 — Helm / K8s workloads (CLI; plan-safe)
############################################

resource "local_file" "m3_nodepool" {
  filename = "${path.module}/.generated/m3-nodepool.yaml"
  content = templatefile("${path.module}/files/m3-nodepool.yaml.tftpl", {
    node_role_name = aws_iam_role.skm_karpenter_node.name
  })
}

resource "local_file" "m3_app" {
  filename = "${path.module}/.generated/m3-app.yaml"
  content = templatefile("${path.module}/files/m3-app.yaml.tftpl", {
    image     = "${aws_ecr_repository.order_processor.repository_url}:latest"
    queue_url = aws_sqs_queue.order.url
  })
}

resource "local_file" "m3_scaledobject" {
  filename = "${path.module}/.generated/m3-scaledobject.yaml"
  content = templatefile("${path.module}/files/m3-scaledobject.yaml.tftpl", {
    queue_url = aws_sqs_queue.order.url
  })
}

resource "null_resource" "m3_k8s_stack" {
  triggers = {
    cluster       = aws_eks_cluster.skm.name
    nodepool_yaml = local_file.m3_nodepool.content
    app_yaml      = local_file.m3_app.content
    scaler_yaml   = local_file.m3_scaledobject.content
    img           = null_resource.order_processor_image.id
    keda_version  = var.keda_version
    karpenter_ver = var.karpenter_version
  }

  depends_on = [
    aws_eks_cluster.skm,
    aws_eks_node_group.addon,
    aws_eks_addon.skm_vpc_cni,
    aws_eks_addon.skm_kube_proxy,
    aws_eks_addon.skm_coredns,
    aws_eks_addon.skm_pod_identity,
    aws_eks_access_entry.skm_karpenter_node,
    aws_ec2_tag.skm_cluster_sg_discovery,
    aws_iam_role_policy.skm_karpenter_controller,
    aws_eks_pod_identity_association.skm_keda_operator,
    aws_eks_pod_identity_association.skm_order_processor,
    null_resource.order_processor_image,
    local_file.m3_nodepool,
    local_file.m3_app,
    local_file.m3_scaledobject,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export AWS_ACCESS_KEY_ID="$${AWS_ACCESS_KEY_ID}"
      export AWS_SECRET_ACCESS_KEY="$${AWS_SECRET_ACCESS_KEY}"
      export AWS_DEFAULT_REGION=ap-northeast-2
      export KUBECONFIG=${path.module}/.generated/skm-eks-cluster.kubeconfig
      rm -f "$KUBECONFIG"
      aws eks update-kubeconfig --region ap-northeast-2 --name ${aws_eks_cluster.skm.name} --kubeconfig "$KUBECONFIG"

      echo "waiting for addon nodegroup node to be Ready..."
      for i in $(seq 1 60); do
        READY=$(kubectl get nodes -l skm/role=addon --no-headers 2>/dev/null | grep -c " Ready" || true)
        [ "$READY" -ge "1" ] && break
        sleep 10
      done

      helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
        --version ${var.karpenter_version} \
        --namespace kube-system \
        --set settings.clusterName=${aws_eks_cluster.skm.name} \
        --set settings.interruptionQueue= \
        --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${aws_iam_role.skm_karpenter_controller.arn}" \
        --set controller.resources.requests.cpu=100m \
        --set controller.resources.requests.memory=256Mi \
        --wait --timeout 10m

      helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
      helm repo update kedacore
      helm upgrade --install keda kedacore/keda \
        --version ${var.keda_version} \
        --namespace keda --create-namespace \
        --set tolerations[0].key=CriticalAddonsOnly \
        --set tolerations[0].operator=Exists \
        --wait --timeout 10m

      for i in $(seq 1 60); do
        kubectl get crd ec2nodeclasses.karpenter.k8s.aws nodepools.karpenter.sh scaledobjects.keda.sh >/dev/null 2>&1 && break
        sleep 5
      done

      kubectl apply -f ${local_file.m3_nodepool.filename}
      kubectl apply -f ${local_file.m3_app.filename}

      echo "waiting for order-processor rollout..."
      kubectl -n skillsmkt rollout status deployment/order-processor --timeout=180s || true

      kubectl apply -f ${local_file.m3_scaledobject.filename}
    EOT
  }
}
