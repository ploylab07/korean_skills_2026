variable "participant_id" {
  type    = string
  default = "53"
}

variable "bastion_key_name" {
  type    = string
  default = ""
}

variable "ssh_public_key" {
  type    = string
  default = ""
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "bastion_password" {
  type    = string
  default = "Skill53##"
}
