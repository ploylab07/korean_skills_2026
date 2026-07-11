# ── App Internal ALB ─────────────────────────────────────────────────────────

resource "aws_lb" "app_alb" {
  name               = "${local.name_prefix}-app-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.app_private_a.id, aws_subnet.app_private_b.id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-alb" })
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Internal ALB security group"
  vpc_id      = aws_vpc.app.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.app_vpc_cidr, local.hub_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-sg" })
}

resource "aws_lb_target_group" "red" {
  name        = "${local.name_prefix}-red-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.app.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "green" {
  name        = "${local.name_prefix}-green-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.app.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.red.arn
  }
}

resource "aws_lb_listener_rule" "red" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.red.arn
  }

  condition {
    path_pattern {
      values = ["/red*"]
    }
  }
}

resource "aws_lb_listener_rule" "green" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  condition {
    path_pattern {
      values = ["/green*"]
    }
  }
}

# ── App Internal NLB (PrivateLink backend) ───────────────────────────────────

resource "aws_lb" "app_internal_nlb" {
  name               = "${local.name_prefix}-app-internal-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.app_private_a.id, aws_subnet.app_private_b.id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-internal-nlb" })
}

resource "aws_lb_target_group" "app_internal_nlb" {
  name        = "${local.name_prefix}-app-int-nlb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.app.id
  target_type = "alb"

  health_check {
    protocol = "HTTP"
    path     = "/health"
    port     = "80"
  }
}

resource "aws_lb_target_group_attachment" "app_alb" {
  target_group_arn = aws_lb_target_group.app_internal_nlb.arn
  target_id        = aws_lb.app_alb.arn
  port             = 80

  depends_on = [aws_lb_listener.app, aws_lb_listener.app_internal_nlb]
}

data "aws_network_interface" "app_vpce" {
  for_each = {
    a = aws_subnet.hub_public_a.id
    b = aws_subnet.hub_public_b.id
  }

  filter {
    name   = "subnet-id"
    values = [each.value]
  }

  filter {
    name   = "description"
    values = ["VPC Endpoint Interface ${aws_vpc_endpoint.app_hub.id}"]
  }

  depends_on = [aws_vpc_endpoint.app_hub]
}

resource "aws_lb_target_group_attachment" "app_vpce" {
  for_each         = data.aws_network_interface.app_vpce
  target_group_arn = aws_lb_target_group.app_external_nlb.arn
  target_id        = each.value.private_ip
  port             = 80
}

data "aws_network_interface" "argo_vpce" {
  for_each = {
    a = aws_subnet.hub_public_a.id
    b = aws_subnet.hub_public_b.id
  }

  filter {
    name   = "subnet-id"
    values = [each.value]
  }

  filter {
    name   = "description"
    values = ["VPC Endpoint Interface ${aws_vpc_endpoint.argo_hub.id}"]
  }

  depends_on = [aws_vpc_endpoint.argo_hub]
}

resource "aws_lb_target_group_attachment" "argo_vpce" {
  for_each         = data.aws_network_interface.argo_vpce
  target_group_arn = aws_lb_target_group.argo_external.arn
  target_id        = each.value.private_ip
  port             = 80
}

resource "aws_lb_listener" "app_internal_nlb" {
  load_balancer_arn = aws_lb.app_internal_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_internal_nlb.arn
  }
}

resource "aws_vpc_endpoint_service" "app" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.app_internal_nlb.arn]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-pl-service" })
}

resource "aws_vpc_endpoint" "app_hub" {
  vpc_id              = aws_vpc.hub.id
  service_name        = aws_vpc_endpoint_service.app.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.hub_public_a.id, aws_subnet.hub_public_b.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = false

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-pl-endpoint" })
}

resource "aws_vpc_endpoint_service_allowed_principal" "app" {
  vpc_endpoint_service_id = aws_vpc_endpoint_service.app.id
  principal_arn           = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
}

# ── App External NLB (Hub VPC) ───────────────────────────────────────────────

resource "aws_lb" "app_external_nlb" {
  name               = "${local.name_prefix}-app-external-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.hub_public_a.id, aws_subnet.hub_public_b.id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-external-nlb" })
}

resource "aws_lb_target_group" "app_external_nlb" {
  name        = "${local.name_prefix}-app-ext-nlb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.hub.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "80"
  }
}

resource "aws_lb_listener" "app_external_nlb" {
  load_balancer_arn = aws_lb.app_external_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_external_nlb.arn
  }
}

resource "aws_security_group" "vpce" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "PrivateLink endpoint SG"
  vpc_id      = aws_vpc.hub.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.hub_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-sg" })
}

# ── ArgoCD NLBs ──────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "argo_internal" {
  name        = "${local.name_prefix}-argo-int-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.app.id
  target_type = "ip"

  health_check {
    protocol = "HTTP"
    path     = "/"
    port     = "80"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "argo_internal" {
  load_balancer_arn = aws_lb.argo_internal_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.argo_internal.arn
  }
}

resource "aws_lb" "argo_internal_nlb" {
  name               = "${local.name_prefix}-argo-internal-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.app_private_a.id, aws_subnet.app_private_b.id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-argo-internal-nlb" })
}

resource "aws_lb" "argo_external_nlb" {
  name               = "${local.name_prefix}-argo-external-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.hub_public_a.id, aws_subnet.hub_public_b.id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-argo-external-nlb" })
}

resource "aws_vpc_endpoint_service" "argo" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.argo_internal_nlb.arn]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-argo-pl-service" })
}

resource "aws_vpc_endpoint" "argo_hub" {
  vpc_id              = aws_vpc.hub.id
  service_name        = aws_vpc_endpoint_service.argo.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.hub_public_a.id, aws_subnet.hub_public_b.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = false

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-argo-pl-endpoint" })
}

resource "aws_lb_target_group" "argo_external" {
  name        = "${local.name_prefix}-argo-ext-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.hub.id
  target_type = "ip"
}

resource "aws_lb_listener" "argo_external" {
  load_balancer_arn = aws_lb.argo_external_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.argo_external.arn
  }
}
