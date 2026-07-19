output "vpc_id" {
  value = aws_vpc.main.id
}

output "bucket_name" {
  value = aws_s3_bucket.web.id
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "alb_dns" {
  value = aws_lb.book.dns_name
}

output "grafana_alb_dns" {
  value = aws_lb.grafana.dns_name
}

output "grafana_url" {
  value = "http://${aws_lb.grafana.dns_name}/d/wskorea26/wskorea26-monitoring"
}

output "grafana_login" {
  value = "${local.grafana_admin_user} / (see var.grafana_admin_password)"
}
