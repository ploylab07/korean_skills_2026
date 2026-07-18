resource "aws_lb" "app" {
  name               = "wsc2026-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.hub_a.id, aws_subnet.hub_b.id]

  tags = {
    Name                            = "wsc2026-app-alb"
    "elbv2.k8s.aws/cluster"       = local.cluster_name
    "ingress.k8s.aws/stack"         = "wsc2026"
    "ingress.k8s.aws/resource"      = "LoadBalancer"
  }
}
