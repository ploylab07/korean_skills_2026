locals {
  account_id = data.aws_caller_identity.current.account_id

  # AMI Amazon Linux 2023 x86_64 (resolved via SSM)
  ami_seoul     = data.aws_ssm_parameter.al2023_seoul.value
  ami_tokyo     = data.aws_ssm_parameter.al2023_tokyo.value
  ami_singapore = data.aws_ssm_parameter.al2023_singapore.value

  common_tags = {
    Project = var.project
    Task    = "day2-008"
  }
}

data "aws_ssm_parameter" "al2023_seoul" {
  provider = aws.seoul
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ssm_parameter" "al2023_tokyo" {
  provider = aws.tokyo
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ssm_parameter" "al2023_singapore" {
  provider = aws.singapore
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_availability_zones" "seoul" {
  provider = aws.seoul
  state    = "available"
}

data "aws_availability_zones" "tokyo" {
  provider = aws.tokyo
  state    = "available"
}

data "aws_availability_zones" "singapore" {
  provider = aws.singapore
  state    = "available"
}

data "aws_availability_zones" "oregon" {
  provider = aws.oregon
  state    = "available"
}

data "aws_ec2_managed_prefix_list" "vpc_lattice_tokyo" {
  provider = aws.tokyo
  name     = "com.amazonaws.ap-northeast-1.vpc-lattice"
}
