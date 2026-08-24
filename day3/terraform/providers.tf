provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Resolve IAM principal for EKS access entries (role ARN when using STS assume-role).
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# Fresh token per Helm/Kubernetes call. Static aws_eks_cluster_auth tokens can be
# issued before access entries exist.
# When the cluster is not up yet, endpoint is empty and the provider defaults to
# http://localhost — start.ps1 bootstraps with enable_k8s_addons=false first.
provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority_data), "")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", module.eks.cluster_name,
      "--region", var.aws_region,
      "--output", "json",
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = try(module.eks.cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority_data), "")

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", module.eks.cluster_name,
        "--region", var.aws_region,
        "--output", "json",
      ]
    }
  }
}
