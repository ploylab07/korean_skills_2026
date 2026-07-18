output "vpc_id" {
  value = aws_vpc.main.id
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "bucket_name" {
  value = aws_s3_bucket.web.bucket
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_id" {
  value = aws_cloudfront_distribution.main.id
}

output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "ecr_url" {
  value = aws_ecr_repository.book.repository_url
}

output "book_tg_arn" {
  value = aws_lb_target_group.book.arn
}

output "grafana_tg_arn" {
  value = aws_lb_target_group.grafana.arn
}
