output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "app_public_ip" {
  value = aws_instance.app.public_ip
}

output "loki_lb_hostname" {
  value = try(data.kubernetes_service.loki.status[0].load_balancer[0].ingress[0].hostname, "")
}

data "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "wsc-logging"
  }
  depends_on = [helm_release.grafana]
}

output "grafana_lb_hostname" {
  value = try(data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].hostname, "")
}
