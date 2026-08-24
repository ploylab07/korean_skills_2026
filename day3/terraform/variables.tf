variable "project" {
  type    = string
  default = "apdev"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"

  validation {
    condition     = var.aws_region == "ap-northeast-2"
    error_message = "The competition resources must be created in ap-northeast-2."
  }
}

variable "cluster_version" {
  type        = string
  description = "EKS Kubernetes minor version supported by the competition account."
  default     = "1.34"
}

variable "db_identifier" {
  type        = string
  description = "Exact RDS DB identifier required by the task."
  default     = "apdev-rds-instance"
}

variable "db_name" {
  type    = string
  default = "dev"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "RDS master password. Supply through TF_VAR_db_password or terraform.tfvars."

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "RDS master password must contain at least 8 characters."
  }
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]

  validation {
    condition     = length(var.node_instance_types) == 1 && var.node_instance_types[0] == "t3.medium"
    error_message = "Only t3.medium is permitted for EKS worker nodes."
  }
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "enable_multi_az_rds" {
  type    = bool
  default = true

  validation {
    condition     = var.enable_multi_az_rds
    error_message = "The task requires a Multi-AZ RDS DB instance."
  }
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "waf_rate_limit" {
  type        = number
  description = "Maximum requests per five-minute evaluation window per source IP."
  default     = 3000
}
