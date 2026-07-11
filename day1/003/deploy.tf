resource "time_sleep" "wait_nodes" {
  depends_on = [
    aws_eks_node_group.addon,
    aws_eks_node_group.workload,
  ]

  create_duration = "90s"
}

resource "null_resource" "k8s_deploy" {
  triggers = {
    cluster_version = aws_eks_cluster.main.version
  }

  depends_on = [
    time_sleep.wait_nodes,
    aws_eks_addon.eks_pod_identity_agent,
    null_resource.ecr_push,
    aws_security_group.alb,
  ]
}

resource "aws_eks_pod_identity_association" "book" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "wsc2026"
  service_account = "wsc2026-book-sa"
  role_arn        = aws_iam_role.book_pod.arn

  depends_on = [null_resource.k8s_deploy]
}
