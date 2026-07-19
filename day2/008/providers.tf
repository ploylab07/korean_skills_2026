provider "aws" {
  alias  = "seoul"
  region = "ap-northeast-2"
}

provider "aws" {
  alias  = "tokyo"
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "singapore"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "oregon"
  region = "us-west-2"
}

# default = seoul (start.cmd / single-region tools)
provider "aws" {
  region = "ap-northeast-2"
}

data "aws_caller_identity" "current" {}

# Helm/kubectl은 apply 시점 kubeconfig(/tmp/skills-sqs-tf.kubeconfig)를 사용.
# kubernetes_manifest 미사용 — 클러스터 생성 전 plan 실패 방지.
provider "helm" {
  kubernetes {
    config_path = "/tmp/skills-sqs-tf.kubeconfig"
  }
}
