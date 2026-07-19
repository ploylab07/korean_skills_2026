variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "bibun" {
  description = "비번호 (S3 버킷·Grafana 계정)"
  type        = string
  default     = "001"
}

variable "grafana_admin_password" {
  type      = string
  default   = "$korea26!!"
  sensitive = true
}

variable "kubeconfig_path" {
  type    = string
  default = ""
}

variable "kubeconfig_context" {
  type    = string
  default = "wskorea26"
}
