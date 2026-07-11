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
  }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  az_a = data.aws_availability_zones.available.names[0]
  az_b = data.aws_availability_zones.available.names[1]

  hub_vpc_cidr = "10.0.0.0/16"
  app_vpc_cidr = "192.168.0.0/16"

  name_prefix = "gj2025"

  common_tags = {
    Project = "gj2025"
  }

  github_repo_url = "https://github.com/${var.github_owner}/${var.github_repo}.git"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "github_owner" {
  type    = string
  default = "jeonghee-seock"
}

variable "github_repo" {
  type    = string
  default = "gj2025-repository"
}

variable "github_token" {
  type      = string
  sensitive = true
  default   = "placeholder-github-token"
}

variable "github_oauth_token" {
  type      = string
  sensitive = true
  default   = "placeholder-oauth-token"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "Skills53#$%"
}

variable "argo_admin_password" {
  type      = string
  sensitive = true
  default   = "Skills53"
}

variable "bastion_key_name" {
  type    = string
  default = "gj2025-bastion-key"
}

variable "bastion_allowed_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
