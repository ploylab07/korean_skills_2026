data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

resource "kubernetes_namespace" "logging" {
  metadata {
    name = "wsc-logging"
  }
  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "5.47.2"
  timeout    = 900
  wait       = true

  values = [yamlencode({
    deploymentMode = "SingleBinary"
    loki = {
      auth_enabled = false
      commonConfig = {
        replication_factor = 1
      }
      storage = {
        type        = "filesystem"
        bucketNames = {
          chunks = "chunks"
          ruler  = "ruler"
          admin  = "admin"
        }
      }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v13"
          index = {
            prefix = "index_"
            period = "24h"
          }
        }]
      }
    }
    singleBinary = {
      replicas = 1
      persistence = {
        enabled      = true
        size         = "10Gi"
        storageClass = "gp2"
      }
    }
    read   = { replicas = 0 }
    write  = { replicas = 0 }
    backend = { replicas = 0 }
    gateway = { enabled = false }
    service = {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
      }
    }
  })]

  depends_on = [kubernetes_namespace.logging, aws_eks_addon.ebs_csi]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "9.2.7"
  timeout    = 900
  wait       = true

  values = [yamlencode({
    adminUser     = local.grafana_admin_user
    adminPassword = local.grafana_admin_password
    service = {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
      }
    }
    datasources = {
      "datasources.yaml" = {
        apiVersion = 1
        datasources = [{
          name      = "Loki"
          type      = "loki"
          url       = "http://loki.${kubernetes_namespace.logging.metadata[0].name}.svc.cluster.local:3100"
          access    = "proxy"
          isDefault = true
        }]
      }
    }
    dashboardProviders = {
      "dashboardproviders.yaml" = {
        apiVersion = 1
        providers = [{
          name            = "wsc"
          orgId           = 1
          folder          = ""
          type            = "file"
          disableDeletion = false
          editable        = true
          options = { path = "/var/lib/grafana/dashboards/wsc" }
        }]
      }
    }
    dashboards = {
      wsc = {
        "wsc2026-container-logs" = {
          json = jsonencode({
            title       = "WSC2026 Container Logs"
            uid         = "wsc2026-container-logs"
            timezone    = "Asia/Seoul"
            refresh     = "5s"
            time = { from = "now-1h", to = "now" }
            panels = [
              {
                id    = 1
                title = "Any Log"
                type  = "logs"
                gridPos = { h = 8, w = 24, x = 0, y = 0 }
                targets = [{ expr = "{namespace=\"wsc-app-log\"}", refId = "A" }]
              },
              {
                id    = 2
                title = "INFO Log Count"
                type  = "timeseries"
                gridPos = { h = 8, w = 12, x = 0, y = 8 }
                targets = [{ expr = "count_over_time({namespace=\"wsc-app-log\"} |= \"INFO\" [1m])", refId = "A" }]
              },
              {
                id    = 3
                title = "ERROR Log Count"
                type  = "timeseries"
                gridPos = { h = 8, w = 12, x = 12, y = 8 }
                targets = [{ expr = "count_over_time({namespace=\"wsc-app-log\"} |= \"ERROR\" [1m])", refId = "A" }]
              },
              {
                id    = 4
                title = "WARNING Log Count"
                type  = "timeseries"
                gridPos = { h = 8, w = 24, x = 0, y = 16 }
                targets = [{ expr = "count_over_time({namespace=\"wsc-app-log\"} |= \"WARNING\" [1m])", refId = "A" }]
              }
            ]
          })
        }
      }
    }
  })]

  depends_on = [helm_release.loki]
}

data "kubernetes_service" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }
  depends_on = [helm_release.loki]
}
