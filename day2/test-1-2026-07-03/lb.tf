resource "aws_security_group" "app_alb" {
  name        = "${local.prefix}-app-alb-sg"
  description = "Internal app ALB - CloudFront only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-app-alb-sg" })
}

resource "aws_lb" "app" {
  name               = "${local.prefix}-app-lb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_alb.id]
  subnets            = [aws_subnet.private_a.id, aws_subnet.private_c.id]

  tags = merge(local.common_tags, { Name = "${local.prefix}-app-lb" })
}

resource "aws_lb_target_group" "app" {
  name        = "${local.prefix}-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 5
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_security_group" "addon_alb" {
  name        = "${local.prefix}-addon-alb-sg"
  description = "Public addon ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-addon-alb-sg" })
}

resource "aws_lb" "addon" {
  name               = "${local.prefix}-addon-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.addon_alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_c.id]

  tags = merge(local.common_tags, { Name = "${local.prefix}-addon-lb" })
}

resource "aws_lb_target_group" "grafana" {
  name        = "${local.prefix}-grafana-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path     = "/grafana/api/health"
    matcher  = "200-399"
    interval = 15
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "prometheus" {
  name        = "${local.prefix}-prometheus-tg"
  port        = 9090
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path     = "/prometheus/-/healthy"
    matcher  = "200-399"
    interval = 15
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "addon" {
  load_balancer_arn = aws_lb.addon.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.addon.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana", "/grafana/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prometheus" {
  listener_arn = aws_lb_listener.addon.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }

  condition {
    path_pattern {
      values = ["/prometheus", "/prometheus/*"]
    }
  }
}
