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
