output "ec2_public_ip" {
  value = aws_instance.data.public_ip
}

output "nlb_dns" {
  value = aws_lb.kafka.dns_name
}

output "flink_application_name" {
  value = "gj2026-data-flink"
}
