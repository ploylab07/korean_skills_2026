output "module1_client_public_ip" {
  value = aws_instance.nosql_client.public_ip
}

output "module2_client_public_ip" {
  value = aws_instance.lattice_client.public_ip
}

output "module2_service_url" {
  value = "http://${aws_vpclattice_service.order.dns_entry[0].domain_name}"
}

output "module3_protected_sg" {
  value = aws_security_group.ceh_protected.id
}

output "module4_cluster" {
  value = aws_eks_cluster.sqs.name
}

output "module4_queue_url" {
  value = aws_sqs_queue.skills.url
}
