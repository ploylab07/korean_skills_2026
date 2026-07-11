output "bastion_public_ip" {
  description = "Bastion Elastic IP"
  value       = aws_eip.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to bastion"
  value       = "ssh -i bastion.pem -p 2222 ec2-user@${aws_eip.bastion.public_ip}"
}

output "app_external_nlb_dns" {
  description = "External NLB DNS for Red/Green API"
  value       = aws_lb.app_external_nlb.dns_name
}

output "argo_external_nlb_dns" {
  description = "External NLB DNS for ArgoCD"
  value       = aws_lb.argo_external_nlb.dns_name
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "ecr_red_url" {
  value = aws_ecr_repository.red.repository_url
}

output "ecr_green_url" {
  value = aws_ecr_repository.green.repository_url
}

output "rds_proxy_endpoint" {
  value = aws_db_proxy.main.endpoint
}

output "tg_red_arn" {
  value = aws_lb_target_group.red.arn
}

output "tg_green_arn" {
  value = aws_lb_target_group.green.arn
}

output "tg_argo_arn" {
  value = aws_lb_target_group.argo_internal.arn
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "fluent_bit_role_arn" {
  value = aws_iam_role.fluent_bit.arn
}

output "lb_controller_role_arn" {
  value = aws_iam_role.aws_load_balancer_controller.arn
}

output "app_vpc_id" {
  value = aws_vpc.app.id
}

output "db_catalog_secret_name" {
  value = aws_secretsmanager_secret.db_catalog.name
}

output "bastion_private_key_ssm" {
  value = aws_ssm_parameter.bastion_private_key.name
}
