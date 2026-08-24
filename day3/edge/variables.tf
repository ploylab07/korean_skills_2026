variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type        = string
  description = "Name prefix from core stack output project_name (e.g. apdev-dev). Required — pass from scripts/07."

  validation {
    condition     = length(var.project_name) > 0
    error_message = "project_name must be set (use core terraform output project_name)."
  }
}

variable "alb_dns_name" {
  type        = string
  description = "DNS name created by the Kubernetes ALB Ingress."
}

variable "image_bucket_name" {
  type        = string
  description = "Private S3 bucket used by the product application."
}
