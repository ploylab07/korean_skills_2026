output "cluster_arn" {
  value       = aws_msk_cluster.this.arn
  description = "ARN of the MSK cluster."
}

output "bucket_name" {
  value       = aws_s3_bucket.alerts.bucket
  description = "S3 bucket that contains alert records."
}

output "table_name" {
  value       = aws_dynamodb_table.sensor_data.name
  description = "DynamoDB table for normal sensor records."
}
