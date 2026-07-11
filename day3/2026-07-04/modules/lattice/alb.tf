resource "aws_lb" "app" {
  name               = "wsc-spoke-app-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.spoke_priv_a.id, aws_subnet.spoke_priv_c.id]

  tags = merge(local.tags, { Name = "wsc-spoke-app-alb" })
}

resource "aws_lb_target_group" "v1" {
  name     = "wsc-spoke-v1-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.spoke.id

  health_check {
    enabled             = true
    path                = "/healthcheck"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(local.tags, { Name = "wsc-spoke-v1-tg" })
}

resource "aws_lb_target_group" "v2" {
  name     = "wsc-spoke-v2-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.spoke.id

  health_check {
    enabled             = true
    path                = "/healthcheck"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(local.tags, { Name = "wsc-spoke-v2-tg" })
}

resource "aws_lb_target_group_attachment" "v1" {
  target_group_arn = aws_lb_target_group.v1.arn
  target_id        = aws_instance.app_v1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "v2" {
  target_group_arn = aws_lb_target_group.v2.arn
  target_id        = aws_instance.app_v2.id
  port             = 8080
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
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

resource "aws_lb_listener_rule" "healthcheck" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Restrict access to api"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/healthcheck"]
    }
  }
}

resource "aws_lb_listener_rule" "version" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.v1.arn
        weight = 90
      }
      target_group {
        arn    = aws_lb_target_group.v2.arn
        weight = 10
      }
    }
  }

  condition {
    path_pattern {
      values = ["/version"]
    }
  }
}
