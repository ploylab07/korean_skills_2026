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

resource "kubernetes_namespace" "scaling" {
  metadata {
    name = "wsc-scaling"
  }

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true
  version          = "2.16.1"

  set {
    name  = "serviceAccount.operator.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.keda_operator.arn
  }

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  namespace        = "kube-system"
  version          = "1.2.1"

  set {
    name  = "settings.clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = aws_eks_cluster.main.endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }

  depends_on = [aws_eks_node_group.main]
}

resource "kubernetes_service_account" "deploy" {
  metadata {
    name      = "wsc-scaling-deploy-sa"
    namespace = kubernetes_namespace.scaling.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.keda_pod.arn
    }
  }
}

resource "kubernetes_deployment" "scaling" {
  metadata {
    name      = "wsc-scaling-deploy"
    namespace = kubernetes_namespace.scaling.metadata[0].name
    labels = {
      dedicated = "scaling"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app       = "wsc-scaling-deploy"
        dedicated = "scaling"
      }
    }

    template {
      metadata {
        labels = {
          app       = "wsc-scaling-deploy"
          dedicated = "scaling"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.deploy.metadata[0].name

        node_selector = {
          dedicated = "scaling"
        }

        container {
          name    = "busybox"
          image   = "busybox:latest"
          command = ["sh", "-c", "sleep infinity"]

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.keda]
}
