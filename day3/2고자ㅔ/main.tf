terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "ap_northeast_2"
  region = "ap-northeast-2"
}

provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
}

resource "tls_private_key" "ssh" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  ssh_public_key      = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh[0].public_key_openssh
  ssh_private_key_pem = var.ssh_private_key_pem != "" ? var.ssh_private_key_pem : tls_private_key.ssh[0].private_key_pem
}

module "cdn" {
  source = "./modules/cdn"

  providers = {
    aws = aws.us_east_1
  }

  participant_id = var.participant_id
}

module "analytics" {
  source = "./modules/analytics"

  providers = {
    aws = aws.ap_southeast_1
  }

  ssh_public_key      = local.ssh_public_key
  ssh_private_key_pem = local.ssh_private_key_pem
}

module "event" {
  source = "./modules/event"

  providers = {
    aws = aws.ap_northeast_2
  }

  ssh_public_key      = local.ssh_public_key
  ssh_private_key_pem = local.ssh_private_key_pem
}

module "keycloak" {
  source = "./modules/keycloak"

  providers = {
    aws = aws.eu_central_1
  }

  ssh_public_key      = local.ssh_public_key
  ssh_private_key_pem = local.ssh_private_key_pem
}
