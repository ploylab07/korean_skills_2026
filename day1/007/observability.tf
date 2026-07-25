resource "aws_cloudwatch_log_group" "book_app" {
  name              = "/unicorn/eks/book-app"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform.arn

  depends_on = [aws_kms_key_policy.platform_replica]
}

# --- Fluent Bit (DaemonSet, all nodes) -> CloudWatch Logs ---
resource "kubernetes_config_map_v1" "fluent_bit" {
  metadata {
    name      = "fluent-bit-config"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "fluent-bit.conf" = <<-EOT
      [SERVICE]
          Flush         1
          Log_Level     info
          Daemon        off
          Parsers_File  parsers.conf

      [INPUT]
          Name              tail
          Tag               book.*
          Path              /var/log/containers/*_unicorn_book-*.log
          Parser            cri
          Refresh_Interval  5
          Mem_Buf_Limit     5MB
          Skip_Long_Lines   On
          DB                /var/log/flb_book.db

      [FILTER]
          Name     grep
          Match    book.*
          Exclude  log path=/health

      [FILTER]
          Name          parser
          Match         book.*
          Key_Name      log
          Parser        book_access
          Reserve_Data  Off

      [FILTER]
          Name    lua
          Match   book.*
          script  normalize.lua
          call    normalize

      [OUTPUT]
          Name                cloudwatch_logs
          Match               book.*
          region              ${local.region}
          log_group_name      ${aws_cloudwatch_log_group.book_app.name}
          log_stream_prefix   unicorn-book-app-
          auto_create_group   false
    EOT

    "parsers.conf" = <<-EOT
      [PARSER]
          Name        cri
          Format      regex
          Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<log>.*)$
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z

      [PARSER]
          Name        book_access
          Format      regex
          Regex       ^.*access method=(?<method>\S+) path=(?<path>\S+) status=(?<status_code>\d+) .*remote_addr=(?:\[(?<ip6>[^\]]+)\]|(?<ip4>[^:\s]+)):\d+.*$
    EOT

    "normalize.lua" = <<-EOT
      function normalize(tag, timestamp, record)
          record["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(timestamp))
          if record["ip4"] ~= nil then
              record["client_ip"] = record["ip4"]
          elseif record["ip6"] ~= nil then
              record["client_ip"] = record["ip6"]
          end
          record["ip4"] = nil
          record["ip6"] = nil
          if record["status_code"] ~= nil then
              record["status_code"] = tonumber(record["status_code"])
          end
          return 1, timestamp, record
      end
    EOT
  }
}

resource "kubernetes_daemon_set_v1" "fluent_bit" {
  metadata {
    name      = "aws-for-fluent-bit"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels    = { app = "aws-for-fluent-bit" }
  }

  spec {
    selector {
      match_labels = { app = "aws-for-fluent-bit" }
    }

    template {
      metadata {
        labels = { app = "aws-for-fluent-bit" }
      }

      spec {
        toleration {
          operator = "Exists"
        }

        container {
          name  = "fluent-bit"
          image = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"

          env {
            name  = "AWS_REGION"
            value = local.region
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
          }

          volume_mount {
            name       = "config"
            mount_path = "/fluent-bit/etc/"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              memory = "200Mi"
            }
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.fluent_bit.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.book_app,
    aws_iam_role_policy.node_fluentbit_logs,
    kubernetes_deployment_v1.book,
  ]
}

# --- kube-prometheus-stack (Prometheus + Grafana), addon nodes only ---
resource "helm_release" "kube_prometheus_stack" {
  name       = "kps"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  timeout    = 900

  # EKS manages the control plane; unicorn=addon-only components probe it via
  # the standard k8s API service, but etcd/scheduler/controller-manager are
  # never reachable — disable their ServiceMonitors entirely.
  set = [
    { name = "kubeControllerManager.enabled", value = "false" },
    { name = "kubeScheduler.enabled", value = "false" },
    { name = "kubeEtcd.enabled", value = "false" },
    { name = "grafana.adminUser", value = local.grafana_admin_user },
    { name = "grafana.nodeSelector.unicorn", value = "addon" },
    { name = "grafana.sidecar.dashboards.enabled", value = "true" },
    { name = "grafana.sidecar.dashboards.label", value = "grafana_dashboard" },
    { name = "prometheus.prometheusSpec.nodeSelector.unicorn", value = "addon" },
    { name = "alertmanager.alertmanagerSpec.nodeSelector.unicorn", value = "addon" },
    { name = "kube-state-metrics.nodeSelector.unicorn", value = "addon" },
    { name = "prometheusOperator.nodeSelector.unicorn", value = "addon" },
    { name = "prometheusOperator.admissionWebhooks.enabled", value = "false" },
    { name = "prometheusOperator.admissionWebhooks.patch.enabled", value = "false" },
    # CloudWatch datasource for the "Book App HTTP Request Duration" panel
    # (ALB TargetResponseTime). Grafana runs on the addon node, so it reads
    # via the node IAM role (cloudwatch:GetMetricData/ListMetrics, see iam.tf).
    { name = "grafana.additionalDataSources[0].name", value = "CloudWatch" },
    { name = "grafana.additionalDataSources[0].type", value = "cloudwatch" },
    { name = "grafana.additionalDataSources[0].access", value = "proxy" },
    { name = "grafana.additionalDataSources[0].jsonData.authType", value = "default" },
    { name = "grafana.additionalDataSources[0].jsonData.defaultRegion", value = local.region },
  ]

  set_sensitive = [
    { name = "grafana.adminPassword", value = local.grafana_admin_password },
  ]

  depends_on = [aws_eks_node_group.addon]
}

resource "kubernetes_config_map_v1" "grafana_dashboard" {
  metadata {
    name      = "unicorn-grafana-dashboard"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "unicorn-grafana-dashboard.json" = file("${path.module}/k8s/dashboards/unicorn-grafana-dashboard.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# Register Book App / Grafana pod IPs into their ALB target groups (no AWS
# Load Balancer Controller — simpler & avoids webhook/CRD failure modes).
resource "null_resource" "register_alb_targets" {
  triggers = {
    deployment = kubernetes_deployment_v1.book.id
    grafana    = helm_release.kube_prometheus_stack.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "sleep 45; ${path.module}/scripts/register-alb-targets.sh"
    environment = {
      AWS_DEFAULT_REGION = local.region
      CLUSTER_NAME       = aws_eks_cluster.main.name
    }
  }

  depends_on = [
    kubernetes_deployment_v1.book,
    kubernetes_service_v1.book,
    helm_release.kube_prometheus_stack,
    aws_lb_target_group.book,
    aws_lb_target_group.grafana,
    aws_security_group_rule.cluster_sg_from_alb_book,
    aws_security_group_rule.cluster_sg_from_alb_grafana,
  ]
}
