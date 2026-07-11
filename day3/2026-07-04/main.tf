terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

module "scaling" {
  source = "./modules/scaling"

  bastion_key_name = var.bastion_key_name
  ssh_public_key   = var.ssh_public_key
}

module "lattice" {
  source = "./modules/lattice"

  participant_id   = var.participant_id
  bastion_key_name = var.bastion_key_name
  ssh_public_key   = var.ssh_public_key
}

module "logging" {
  source = "./modules/logging"

  participant_id   = var.participant_id
  bastion_key_name = var.bastion_key_name
  ssh_public_key   = var.ssh_public_key
}

module "rest_api" {
  source = "./modules/rest_api"
}
