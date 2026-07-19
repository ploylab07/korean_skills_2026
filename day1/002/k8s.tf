resource "null_resource" "taint_app_nodes" {
  triggers = {
    nodegroup = aws_eks_node_group.app.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}
      for n in $(kubectl get nodes -l node-type=app -o name); do
        kubectl taint nodes "$${n#node/}" node-type=app:NoSchedule --overwrite || true
      done
    EOT
  }

  depends_on = [aws_eks_node_group.app]
}

resource "kubernetes_namespace" "wskorea26" {
  metadata {
    name = "wskorea26"
  }
  depends_on = [null_resource.taint_app_nodes]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [aws_eks_node_group.addon]
}

resource "kubernetes_deployment" "book" {
  metadata {
    name      = "book"
    namespace = kubernetes_namespace.wskorea26.metadata[0].name
    labels    = { app = "book" }
  }

  spec {
    replicas = 2
    selector {
      match_labels = { app = "book" }
    }
    template {
      metadata {
        labels = { app = "book" }
      }
      spec {
        node_selector = {
          "node-type" = "app"
        }
        toleration {
          key      = "node-type"
          operator = "Equal"
          value    = "app"
          effect   = "NoSchedule"
        }
        container {
          name  = "book"
          image = "${aws_ecr_repository.book.repository_url}:stable"
          port {
            container_port = 8080
          }
          env {
            name  = "AWS_REGION"
            value = var.region
          }
          env {
            name  = "TABLE_NAME"
            value = aws_dynamodb_table.data.name
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [null_resource.book_image, aws_eks_node_group.app]
}

resource "kubernetes_service" "book" {
  metadata {
    name      = "book"
    namespace = kubernetes_namespace.wskorea26.metadata[0].name
  }
  spec {
    selector = { app = "book" }
    port {
      port        = 8080
      target_port = 8080
      name        = "http"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kps"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 900

  set {
    name  = "grafana.adminUser"
    value = local.grafana_admin_user
  }
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
  set {
    name  = "grafana.nodeSelector.node-type"
    value = "addon"
  }
  set {
    name  = "grafana.sidecar.dashboards.enabled"
    value = "true"
  }
  set {
    name  = "prometheus.prometheusSpec.nodeSelector.node-type"
    value = "addon"
  }
  set {
    name  = "alertmanager.alertmanagerSpec.nodeSelector.node-type"
    value = "addon"
  }
  set {
    name  = "kube-state-metrics.nodeSelector.node-type"
    value = "addon"
  }
  set {
    name  = "prometheusOperator.nodeSelector.node-type"
    value = "addon"
  }
  set {
    name  = "prometheusOperator.admissionWebhooks.enabled"
    value = "false"
  }
  set {
    name  = "prometheusOperator.admissionWebhooks.patch.enabled"
    value = "false"
  }

  depends_on = [aws_eks_node_group.addon]
}

resource "kubernetes_config_map" "dashboard" {
  metadata {
    name      = "wskorea26-dashboard"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "wskorea26-monitoring.json" = file("${path.module}/k8s/monitoring/dashboard.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "helm_release" "fluent_bit" {
  name       = "aws-for-fluent-bit"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  set {
    name  = "nodeSelector.node-type"
    value = "addon"
  }
  set {
    name  = "cloudWatchLogs.enabled"
    value = "true"
  }
  set {
    name  = "cloudWatchLogs.region"
    value = var.region
  }
  set {
    name  = "cloudWatchLogs.logGroupName"
    value = "/aws/eks/wskorea26-cluster/pods"
  }
  set {
    name  = "cloudWatchLogs.autoCreateGroup"
    value = "true"
  }
  set {
    name  = "firehose.enabled"
    value = "false"
  }
  set {
    name  = "kinesis.enabled"
    value = "false"
  }
  set {
    name  = "elasticsearch.enabled"
    value = "false"
  }

  depends_on = [aws_eks_node_group.addon]
}

# Register book pod IPs to ALB TG (IP mode)
resource "null_resource" "register_book_targets" {
  triggers = {
    deployment = kubernetes_deployment.book.id
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/register-book-targets.sh"
    environment = {
      KUBECONFIG = coalesce(pathexpand("~/.kube/wskorea26.yaml"), pathexpand("~/.kube/config"))
      AWS_DEFAULT_REGION = var.region
    }
  }

  depends_on = [kubernetes_deployment.book, aws_lb_target_group.book]
}
