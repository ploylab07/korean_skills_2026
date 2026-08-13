provider "aws" {
  region = "ap-northeast-2"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  bib          = "006"
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.id
  azs          = ["ap-northeast-2a", "ap-northeast-2b"]
  cluster_name = "gj2026-eks-cluster"
  bucket_name  = "gj2026-static-${local.bib}"
  common_tags = {
    Project = "gj2026"
    Bib     = local.bib
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", "ap-northeast-2"]
  }
}
