variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key_pem" {
  type      = string
  sensitive = true
}
