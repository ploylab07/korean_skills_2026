variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "bucket_suffix" {
  type    = string
  default = "skls"
}

variable "contestant_number" {
  type    = string
  default = "003"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
  default   = "Skills$#$@!"
}
