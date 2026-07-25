output "alb_dns" {
  value = aws_lb.analytics.dns_name
}

output "ec2_id" {
  value = aws_instance.analytics.id
}

output "stream_name" {
  value = aws_kinesis_stream.orders.name
}
