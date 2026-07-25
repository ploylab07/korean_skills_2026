output "vpc_id" {
  value = aws_vpc.main.id
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "ecr_repository_url" {
  value = aws_ecr_repository.book.repository_url
}

output "bastion_instance_id" {
  value = aws_instance.bastion.id
}

output "cloudfront_domain" {
  value = try(aws_cloudfront_distribution.cdn[0].domain_name, null)
}

output "lambda_function_url" {
  value = aws_lambda_function_url.book_get.function_url
}

output "bucket_name" {
  value = aws_s3_bucket.static.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.book.name
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "hub_subnet_ids" {
  value = [aws_subnet.hub_a.id, aws_subnet.hub_b.id]
}

output "mark_sg_id" {
  value = aws_security_group.mark.id
}
