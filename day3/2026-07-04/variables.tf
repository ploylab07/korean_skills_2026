variable "participant_id" {
  type        = string
  description = "비번호 (Grafana 계정, Lattice Bastion 등에 사용)"
  default     = "53"
}

variable "bastion_key_name" {
  type        = string
  description = "Bastion SSH 키 페어 이름 (없으면 생성)"
  default     = ""
}

variable "ssh_public_key" {
  type        = string
  description = "Bastion 접속용 SSH 공개키"
  default     = ""
}
