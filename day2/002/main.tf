terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
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
  alias  = "eu_west_1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "ap_northeast_1"
  region = "ap-northeast-1"
}

module "workflow" {
  source = "./modules/workflow"

  providers = {
    aws = aws.ap_southeast_1
  }

  participant_id = var.participant_id
}

module "analytics" {
  source = "./modules/analytics"

  providers = {
    aws = aws.ap_northeast_2
  }
}

module "event" {
  source = "./modules/event"

  providers = {
    aws = aws.eu_west_1
  }
}

module "msk" {
  source = "./modules/msk"

  providers = {
    aws = aws.ap_northeast_1
  }

  participant_id = var.participant_id
}
