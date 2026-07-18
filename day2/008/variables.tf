variable "project" {
  type    = string
  default = "skills-008"
}

variable "eks_version" {
  type    = string
  default = "1.31"
}

variable "karpenter_version" {
  type    = string
  default = "1.3.3"
}

variable "keda_version" {
  type    = string
  default = "2.16.1"
}
