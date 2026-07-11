provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  az_a = "ap-northeast-2a"
  az_c = "ap-northeast-2c"

  tags = {
    Project = "wsc-scaling"
  }
}
