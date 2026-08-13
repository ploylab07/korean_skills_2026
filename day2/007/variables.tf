variable "player_number" {
  description = "Skills player number"
  type        = string
  default     = "007"
}

variable "karpenter_version" {
  type    = string
  default = "1.3.3"
}

variable "keda_version" {
  type    = string
  default = "2.16.1"
}

variable "eks_version" {
  type    = string
  default = "1.35"
}
