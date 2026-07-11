terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  az_a = [for az in data.aws_availability_zones.available.names : az if endswith(az, "a")][0]
  az_c = [for az in data.aws_availability_zones.available.names : az if endswith(az, "c")][0]

  vpc_cidr = "10.0.0.0/16"
  prefix   = "wsc"

  common_tags = {
    Project = "wsc"
  }

  bastion_password = "Skill53##"
  grafana_password = "Skill53##"
  node_password    = "Skill53##"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "bastion_allowed_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
