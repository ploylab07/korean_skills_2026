output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "bastion_public_ip" {
  description = "Bastion Elastic IP (stop/start 후에도 동일)"
  value       = aws_eip.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Bastion EC2 Instance ID"
  value       = aws_instance.bastion.id
}

output "ecr_about_repository_url" {
  description = "About ECR repository URL"
  value       = aws_ecr_repository.about.repository_url
}

output "ecr_projects_repository_url" {
  description = "Projects ECR repository URL"
  value       = aws_ecr_repository.projects.repository_url
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront HTTPS 접속 도메인"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_url_about" {
  description = "About 페이지 테스트 URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/about"
}

output "cloudfront_url_projects" {
  description = "Projects 페이지 테스트 URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/projects"
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}
