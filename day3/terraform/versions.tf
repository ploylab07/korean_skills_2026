terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # Versions must exist in build/tf-mirror (Windows offline contest PC).
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.56.0, <= 6.60.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}
