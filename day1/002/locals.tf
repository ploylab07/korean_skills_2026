locals {
  account_id   = data.aws_caller_identity.current.account_id
  cluster_name = "wskorea26-cluster"
  bucket_name  = "wskorea26-concert-bucket-${var.bibun}"

  # 문제 Reference01: pub/priv subnet-c → 2c, subnet-d → 2d
  az_c = "ap-northeast-2c"
  az_d = "ap-northeast-2d"

  cache_policy_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  origin_req_cors_s3     = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  origin_req_all_viewer  = "216adef6-5c7f-47e4-b989-5492eafa07d3"

  grafana_admin_user = "skills-${var.bibun}-admin"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
