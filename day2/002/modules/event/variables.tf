variable "region" {
  description = "Region of the aliased AWS provider."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = var.region == "eu-west-1"
    error_message = "This module is intended for eu-west-1."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to delete non-empty CloudTrail and Config buckets."
  type        = bool
  default     = true
}
