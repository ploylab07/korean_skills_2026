provider "aws" {
  region = "ap-northeast-2"
}

# Platform KMS key (multi-region primary) and CloudFront/WAF must live in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  bib          = "007"
  account_id   = data.aws_caller_identity.current.account_id
  region       = "ap-northeast-2"
  azs          = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
  az_suffixes  = ["a", "b", "c"]
  cluster_name = "unicorn-eks-cluster"
  bucket_name  = "unicorn-web-${local.account_id}"

  vpc_cidr = "10.97.0.0/16"

  grafana_admin_user     = "skills${local.bib}"
  grafana_admin_password = "HelloKrSkills!${local.bib}@"

  common_tags = {
    Project = "unicorn"
    Bib     = local.bib
  }

  is_windows     = substr(pathexpand("~"), 1, 1) == ":"
  terraform_bin  = replace(abspath("${path.module}/../../build/.bin"), "\\", "/")
  aws_bin        = "${local.terraform_bin}/aws.exe"
  aws_exec_cmd   = local.is_windows && fileexists(local.aws_bin) ? local.aws_bin : (local.is_windows ? "aws.exe" : "aws")
  prometheus_chart = replace(abspath("${path.module}/charts/kube-prometheus-stack-66.2.1.tgz"), "\\", "/")
}

# Kubernetes / Helm providers talk to the cluster using a short-lived exec
# token (aws eks get-token) so no static kubeconfig/credentials are stored.
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = local.aws_exec_cmd
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = local.aws_exec_cmd
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
    }
  }
}
