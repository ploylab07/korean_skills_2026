output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "alb_dns" {
  description = "unicorn-alb (internal) DNS name — only reachable via unicorn-svc-cf VPC origin"
  value       = aws_lb.book.dns_name
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.unicorn.domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.web.id
}

output "grafana_alb_dns" {
  value = aws_lb.grafana.dns_name
}

output "grafana_login" {
  value     = "${local.grafana_admin_user} / ${local.grafana_admin_password}"
  sensitive = true
}

output "ecr_repository_url" {
  value = aws_ecr_repository.book.repository_url
}

output "lambda_function_name" {
  value = aws_lambda_function.get_booking.function_name
}

output "audit_role_arn" {
  value = aws_iam_role.audit.arn
}
