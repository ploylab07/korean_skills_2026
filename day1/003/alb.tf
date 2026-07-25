# ALB is created by AWS Load Balancer Controller via Ingress
# (annotation alb.ingress.kubernetes.io/load-balancer-name: wsc2026-app-alb).
# CloudFront attaches after Ingress is ready — see variable alb_dns_name.

variable "alb_dns_name" {
  type        = string
  default     = ""
  description = "ALB DNS name from Ingress. Empty skips CloudFront origins that need ALB."
}

variable "enable_cdn" {
  type    = bool
  default = false
}
