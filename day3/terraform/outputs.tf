output "project_name" {
  value = local.name
}

output "aws_region" {
  value = var.aws_region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "rds_identifier" {
  value = aws_db_instance.main.identifier
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "rds_port" {
  value = aws_db_instance.main.port
}

output "db_name" {
  value = var.db_name
}

output "db_username" {
  value = var.db_username
}

output "image_bucket_name" {
  value = aws_s3_bucket.images.bucket
}

output "image_bucket_arn" {
  value = aws_s3_bucket.images.arn
}

output "alb_log_bucket_name" {
  value = aws_s3_bucket.alb_logs.bucket
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "waf_acl_arn" {
  value = aws_wafv2_web_acl.main.arn
}

output "product_pod_role_arn" {
  value = aws_iam_role.product_pod.arn
}

output "db_init_pod_role_arn" {
  value = aws_iam_role.db_init_pod.arn
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.apps : name => repo.repository_url }
}

output "sns_alert_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
