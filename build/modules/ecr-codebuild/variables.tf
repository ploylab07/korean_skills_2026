variable "name_prefix" {
  type        = string
  description = "Prefix for CodeBuild / S3 / IAM names"
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "ecr_repository_name" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "ecr_kms_key_arn" {
  type    = string
  default = null
}

variable "context_dir" {
  type        = string
  description = "Directory zipped and sent to CodeBuild (must contain Dockerfile + build context)"
}

variable "excludes" {
  type        = list(string)
  description = "Glob patterns excluded from the source zip"
  default = [
    ".terraform",
    ".terraform/**",
    "*.tf",
    "*.tfvars",
    "*.md",
    "*.sh",
    "scripts",
    "scripts/**",
    "mark.sh",
    ".git",
    ".git/**",
    "terraform.tfstate*",
    ".build",
    ".build/**",
  ]
}

variable "dockerfile" {
  type    = string
  default = "Dockerfile"
}

variable "image_tags" {
  type        = list(string)
  description = "Tags to apply and push (e.g. [\"stable\"] or [\"v1.0.0\",\"latest\"])"
  default     = ["stable"]
}

variable "build_timeout_min" {
  type    = number
  default = 30
}
