variable "participant_id" {
  description = "비번호 (S3 버킷 등에 사용)"
  type        = string
  default     = "563"
}

variable "ssh_public_key" {
  description = "EC2 SSH 공개키 (미입력 시 Terraform이 생성)"
  type        = string
  default     = ""
}

variable "ssh_private_key_pem" {
  description = "EC2 SSH 개인키 PEM (미입력 시 Terraform이 생성)"
  type        = string
  default     = ""
  sensitive   = true
}
