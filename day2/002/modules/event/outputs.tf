output "instance_id" {
  description = "ID of the EC2 instance monitored by the stop-remediation Lambda."
  value       = aws_instance.event.id
}

output "sg_id" {
  description = "ID of the security group whose ingress is automatically removed."
  value       = aws_security_group.event.id
}

output "topic_arn" {
  description = "ARN of the SNS topic used for alerts."
  value       = aws_sns_topic.alert.arn
}
