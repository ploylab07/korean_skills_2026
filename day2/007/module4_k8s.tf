############################################
# Module 4 — Helm / K8s workloads (CLI; plan-safe)
############################################

resource "local_file" "m4_app" {
  filename = "${path.module}/.generated/m4-app.yaml"
  content = templatefile("${path.module}/files/m4-app.yaml.tftpl", {
    image      = "${aws_ecr_repository.log_generator.repository_url}:latest"
    app_tg_arn = aws_lb_target_group.o11y_app.arn
  })
}

resource "local_file" "m4_grafana" {
  filename = "${path.module}/.generated/m4-grafana.yaml"
  content = templatefile("${path.module}/files/m4-grafana.yaml.tftpl", {
    admin_user     = local.grafana_admin_user
    admin_password = local.grafana_admin_password
    grafana_tg_arn = aws_lb_target_group.o11y_grafana.arn
  })
}

resource "null_resource" "m4_k8s_stack" {
  triggers = {
    cluster      = aws_eks_cluster.o11y.name
    app_yaml     = local_file.m4_app.content
    grafana_yaml = local_file.m4_grafana.content
    otel_yaml    = filemd5("${path.module}/k8s/m4-otel.yaml")
    img          = null_resource.log_generator_image.id
  }

  depends_on = [
    aws_eks_cluster.o11y,
    aws_eks_node_group.o11y,
    aws_eks_addon.o11y_vpc_cni,
    aws_eks_addon.o11y_kube_proxy,
    aws_eks_addon.o11y_coredns,
    aws_eks_addon.o11y_pod_identity,
    aws_eks_addon.o11y_ebs_csi,
    aws_iam_role_policy.alb_controller,
    aws_security_group_rule.nodes_from_alb_app,
    aws_security_group_rule.nodes_from_alb_grafana,
    aws_lb_listener.o11y_app,
    aws_lb_listener.o11y_grafana,
    null_resource.log_generator_image,
    local_file.m4_app,
    local_file.m4_grafana,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export AWS_ACCESS_KEY_ID="$${AWS_ACCESS_KEY_ID}"
      export AWS_SECRET_ACCESS_KEY="$${AWS_SECRET_ACCESS_KEY}"
      export AWS_DEFAULT_REGION=ap-northeast-1
      export KUBECONFIG=${path.module}/.generated/o11y-cluster.kubeconfig
      rm -f "$KUBECONFIG"
      aws eks update-kubeconfig --region ap-northeast-1 --name ${aws_eks_cluster.o11y.name} --kubeconfig "$KUBECONFIG"

      echo "waiting for nodes to be Ready..."
      for i in $(seq 1 60); do
        READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || true)
        [ "$READY" -ge "2" ] && break
        sleep 10
      done

      kubectl apply -f ${path.module}/files/m4-storageclass.yaml
      kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

      helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
      helm repo update eks
      helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --namespace kube-system \
        --set clusterName=${aws_eks_cluster.o11y.name} \
        --set region=ap-northeast-1 \
        --set vpcId=${aws_vpc.m4.id} \
        --set serviceAccount.create=true \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${aws_iam_role.alb_controller.arn}" \
        --wait --timeout 10m

      for i in $(seq 1 60); do
        kubectl get crd targetgroupbindings.elbv2.k8s.aws >/dev/null 2>&1 && break
        sleep 5
      done

      kubectl apply -f ${local_file.m4_app.filename}

      helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
      helm repo update grafana
      helm upgrade --install o11y-loki grafana/loki \
        --version 6.55.0 \
        --namespace monitoring --create-namespace \
        --set loki.auth_enabled=false \
        --set loki.useTestSchema=true \
        --set loki.commonConfig.replication_factor=1 \
        --set loki.storage.type=filesystem \
        --set loki.storage.bucketNames.chunks=chunks \
        --set loki.storage.bucketNames.ruler=ruler \
        --set loki.storage.bucketNames.admin=admin \
        --set loki.limits_config.allow_structured_metadata=true \
        --set deploymentMode=SingleBinary \
        --set singleBinary.replicas=1 \
        --set backend.replicas=0 \
        --set read.replicas=0 \
        --set write.replicas=0 \
        --set gateway.enabled=false \
        --set chunksCache.enabled=false \
        --set resultsCache.enabled=false \
        --set test.enabled=false \
        --set lokiCanary.enabled=false \
        --set monitoring.selfMonitoring.enabled=false \
        --set monitoring.serviceMonitor.enabled=false \
        --wait --timeout 10m

      kubectl apply -f ${path.module}/k8s/m4-otel.yaml
      kubectl apply -f ${local_file.m4_grafana.filename}

      kubectl -n o11y rollout status deployment/log-generator --timeout=180s || true
      kubectl -n monitoring rollout status deployment/o11y-grafana --timeout=180s || true
    EOT
  }
}
