terraform {
  required_version = ">= 1.5.0"

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
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0, < 3.4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8.0"
    }
  }
}
