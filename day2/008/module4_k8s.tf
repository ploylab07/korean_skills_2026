############################################
# Module 4 — Helm / K8s workloads
############################################

resource "kubernetes_namespace" "karpenter" {
  metadata { name = "karpenter" }
  depends_on = [aws_eks_fargate_profile.karpenter]
}

resource "kubernetes_namespace" "keda" {
  metadata { name = "keda" }
  depends_on = [aws_eks_fargate_profile.keda]
}

resource "kubernetes_namespace" "skills_sqs" {
  metadata { name = "skills-sqs" }
  depends_on = [aws_eks_cluster.sqs]
}

resource "null_resource" "coredns_restart" {
  depends_on = [aws_eks_fargate_profile.coredns]
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster --kubeconfig /tmp/skills-sqs-tf.kubeconfig
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
  namespace        = kubernetes_namespace.karpenter.metadata[0].name
  create_namespace = false
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
  ]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_version
  namespace        = kubernetes_namespace.keda.metadata[0].name
  create_namespace = false
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
  ]
}

resource "kubernetes_manifest" "ec2nodeclass" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "skills-sqs-nodeclass"
    }
    spec = {
      role = aws_iam_role.karpenter_node.name
      amiSelectorTerms = [{
        alias = "al2023@latest"
      }]
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = "skills-sqs-cluster" }
      }]
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = "skills-sqs-cluster" }
      }]
      tags = { Name = "skills-sqs-karpenter-node" }
    }
  }
  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "nodepool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "skills-sqs-nodepool"
    }
    spec = {
      template = {
        metadata = {
          labels = { "skills-nodepool" = "event-worker" }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "skills-sqs-nodeclass"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "kubernetes.amazonaws.com/instance-category", operator = "In", values = ["t", "m", "c"] },
            { key = "kubernetes.amazonaws.com/instance-cpu", operator = "In", values = ["2", "4"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
          ]
        }
      }
      limits = { cpu = "100" }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  }
  depends_on = [kubernetes_manifest.ec2nodeclass]
}

resource "kubernetes_service_account" "sqs_worker" {
  metadata {
    name      = "sqs-worker-sa"
    namespace = kubernetes_namespace.skills_sqs.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.sqs_worker.arn
    }
  }
}

resource "kubernetes_deployment" "sqs_worker" {
  metadata {
    name      = "sqs-worker"
    namespace = kubernetes_namespace.skills_sqs.metadata[0].name
  }
  spec {
    replicas = 0
    selector {
      match_labels = { app = "sqs-worker" }
    }
    template {
      metadata {
        labels = { app = "sqs-worker" }
      }
      spec {
        service_account_name = kubernetes_service_account.sqs_worker.metadata[0].name
        node_selector = {
          "karpenter.sh/nodepool" = "skills-sqs-nodepool"
          "skills-nodepool"       = "event-worker"
        }
        container {
          name  = "worker"
          image = "${aws_ecr_repository.worker.repository_url}:latest"
          env {
            name  = "SQS_QUEUE_URL"
            value = aws_sqs_queue.skills.url
          }
          env {
            name  = "AWS_REGION"
            value = "us-west-2"
          }
          env {
            name  = "PROCESSING_SECONDS"
            value = "5"
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
  depends_on = [null_resource.worker_image, kubernetes_manifest.nodepool]
}

resource "kubernetes_manifest" "trigger_auth" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"
    metadata = {
      name      = "sqs-worker-trigger-auth"
      namespace = "skills-sqs"
    }
    spec = {
      podIdentity = { provider = "aws" }
    }
  }
  depends_on = [helm_release.keda, kubernetes_namespace.skills_sqs]
}

resource "kubernetes_manifest" "scaledobject" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "sqs-worker-scaledobject"
      namespace = "skills-sqs"
    }
    spec = {
      scaleTargetRef = { name = "sqs-worker" }
      minReplicaCount = 0
      maxReplicaCount = 6
      pollingInterval = 15
      cooldownPeriod  = 30
      triggers = [{
        type = "aws-sqs-queue"
        authenticationRef = { name = "sqs-worker-trigger-auth" }
        metadata = {
          queueURL       = aws_sqs_queue.skills.url
          queueLength    = "2"
          awsRegion      = "us-west-2"
          identityOwner  = "operator"
        }
      }]
    }
  }
  depends_on = [
    helm_release.keda,
    kubernetes_deployment.sqs_worker,
    kubernetes_manifest.trigger_auth,
  ]
}
