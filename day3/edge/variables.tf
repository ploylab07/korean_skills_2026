variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "apdev-dev"
}

variable "alb_dns_name" {
  type        = string
  description = "DNS name created by the Kubernetes ALB Ingress."
}

variable "image_bucket_name" {
  type        = string
  description = "Private S3 bucket used by the product application."
}
