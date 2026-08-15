locals {
  common_tags = {
    Project = "wsc2026"
  }

  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
  account_id = data.aws_caller_identity.current.account_id

  cluster_name = "wsc2026-eks-cluster"
  # wsc2026-static-<4영문>-<비번호>-bucket
  bucket_name = "wsc2026-static-skil-003-bucket"

  grafana_admin_password = "Skills$#$@!"

  cache_policy_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}
