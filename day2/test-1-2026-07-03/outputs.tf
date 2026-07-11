output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.main.repository_url
}

output "app_target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "grafana_target_group_arn" {
  value = aws_lb_target_group.grafana.arn
}

output "prometheus_target_group_arn" {
  value = aws_lb_target_group.prometheus.arn
}

output "app_pod_role_arn" {
  value = aws_iam_role.app_pod.arn
}

output "fluent_bit_role_arn" {
  value = aws_iam_role.fluent_bit.arn
}

output "lb_controller_role_arn" {
  value = aws_iam_role.aws_lb_controller.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.pod.name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "app_alb_sg" {
  value = aws_security_group.app_alb.id
}
