provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "wskorea26"
    }
  }
}

# kubeconfig는 EKS 생성 후 scripts/kubeconfig.sh 또는 null_resource로 갱신
provider "kubernetes" {
  config_path    = coalesce(var.kubeconfig_path, "${pathexpand("~")}/.kube/wskorea26.yaml")
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = coalesce(var.kubeconfig_path, "${pathexpand("~")}/.kube/wskorea26.yaml")
    config_context = var.kubeconfig_context
  }
}
