# Default provider = seoul (ap-northeast-2)
provider "aws" {
  region = "ap-northeast-2"
}

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
  alias  = "virginia"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "singapore" {
  provider = aws.singapore
  state    = "available"
}

data "aws_availability_zones" "virginia" {
  provider = aws.virginia
  state    = "available"
}

data "aws_availability_zones" "seoul" {
  provider = aws.seoul
  state    = "available"
}

data "aws_availability_zones" "tokyo" {
  provider = aws.tokyo
  state    = "available"
}
