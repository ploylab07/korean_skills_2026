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

data "aws_eks_cluster_auth" "sqs" {
  provider = aws.oregon
  name     = aws_eks_cluster.sqs.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.sqs.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.sqs.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.sqs.token
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.sqs.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.sqs.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.sqs.token
  }
}
