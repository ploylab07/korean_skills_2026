resource "kubernetes_namespace_v1" "unicorn" {
  metadata {
    name = "unicorn"
  }
  depends_on = [aws_eks_node_group.app]
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [aws_eks_node_group.addon]
}

resource "kubernetes_service_account_v1" "book" {
  metadata {
    name      = "book"
    namespace = kubernetes_namespace_v1.unicorn.metadata[0].name
  }
}

resource "kubernetes_deployment_v1" "book" {
  metadata {
    name      = "unicorn-book-app-deploy"
    namespace = kubernetes_namespace_v1.unicorn.metadata[0].name
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
        service_account_name = kubernetes_service_account_v1.book.metadata[0].name

        node_selector = {
          unicorn = "app"
        }

        termination_grace_period_seconds = 30

        container {
          name  = "book"
          image = "${aws_ecr_repository.book.repository_url}:v1.0.0"

          port {
            container_port = 8080
          }

          env {
            name  = "AWS_REGION"
            value = local.region
          }

          env {
            name  = "TABLE_NAME"
            value = aws_dynamodb_table.concert.name
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          # distroless has no shell, so a graceful-shutdown preStop must use
          # httpGet (exec is unavailable).
          lifecycle {
            pre_stop {
              http_get {
                path = "/health"
                port = 8080
              }
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.push_book_image,
    aws_eks_pod_identity_association.book_app,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.coredns,
  ]
}

resource "kubernetes_service_v1" "book" {
  metadata {
    name      = "unicorn-book-app-svc"
    namespace = kubernetes_namespace_v1.unicorn.metadata[0].name
  }

  spec {
    selector = { app = "book" }

    port {
      port        = 8080
      target_port = 8080
      name        = "http"
    }
  }

  depends_on = [kubernetes_deployment_v1.book]
}
