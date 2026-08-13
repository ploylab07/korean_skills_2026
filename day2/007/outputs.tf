output "account_id" {
  value = local.account_id
}

output "module1_ec2_public_ip" {
  value = aws_instance.nosql_app.public_ip
}

output "module2_cloudfront_domain" {
  value = aws_cloudfront_distribution.landing.domain_name
}

output "module2_landing_bucket" {
  value = aws_s3_bucket.landing.id
}

output "module3_cluster_name" {
  value = aws_eks_cluster.skm.name
}

output "module3_sqs_queue_url" {
  value = aws_sqs_queue.order.url
}

output "module4_cluster_name" {
  value = aws_eks_cluster.o11y.name
}

output "module4_app_alb_dns" {
  value = aws_lb.o11y_app.dns_name
}

output "module4_grafana_alb_dns" {
  value = aws_lb.o11y_grafana.dns_name
}

output "module4_grafana_admin_user" {
  value = local.grafana_admin_user
}
