locals {
  vpc_cidr = "10.0.0.0/16"

  public_subnets = {
    a = { cidr = "10.0.1.0/24", az_suffix = "a", name = "wsi-public-a" }
    b = { cidr = "10.0.2.0/24", az_suffix = "b", name = "wsi-public-b" }
  }

  private_subnets = {
    a = { cidr = "10.0.3.0/24", az_suffix = "a", name = "wsi-private-a" }
    b = { cidr = "10.0.4.0/24", az_suffix = "b", name = "wsi-private-b" }
  }

  azs = [
    for suffix in ["a", "b"] : "${var.aws_region}${suffix}"
  ]
}
