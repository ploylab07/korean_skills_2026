output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "sqs_url" {
  value = aws_sqs_queue.main.url
}

output "karpenter_node_role" {
  value = aws_iam_role.karpenter_node.name
}
