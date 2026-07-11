provider "aws" {
  region = var.region
}

locals {
  az_a = "ap-southeast-1a"
  az_c = "ap-southeast-1c"
  tags = { Project = "wsc-lattice" }
}
