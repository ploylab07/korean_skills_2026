resource "aws_lb" "main" {
  name               = "gj2026-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = merge(local.common_tags, { Name = "gj2026-alb" })
}

resource "aws_lb_target_group" "book" {
  name        = "gj2026-book-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "gj2026-book-tg" })
}

resource "aws_lb_target_group" "grafana" {
  name        = "gj2026-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path     = "/api/health"
    matcher  = "200"
    interval = 30
  }

  tags = merge(local.common_tags, { Name = "gj2026-grafana-tg" })
}

resource "aws_lb_target_group" "lambda" {
  name        = "gj2026-lambda-tg"
  target_type = "lambda"

  tags = merge(local.common_tags, { Name = "gj2026-lambda-tg" })
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.reservation.arn
  depends_on       = [aws_lambda_permission.alb]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
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

# POST /v1/book -> book
resource "aws_lb_listener_rule" "book_post" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    path_pattern {
      values = ["/v1/book", "/v1/book/"]
    }
  }

  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}

# GET /v1/book -> 405 Method Not Allowed
resource "aws_lb_listener_rule" "book_get_405" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 11

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Method Not Allowed"
      status_code  = "405"
    }
  }

  condition {
    path_pattern {
      values = ["/v1/book", "/v1/book/"]
    }
  }

  condition {
    http_request_method {
      values = ["GET"]
    }
  }
}

# GET /health -> book
resource "aws_lb_listener_rule" "health" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    path_pattern {
      values = ["/health", "/health/"]
    }
  }
}

# /reservation -> lambda
resource "aws_lb_listener_rule" "reservation" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    path_pattern {
      values = ["/reservation", "/reservation/"]
    }
  }
}

# /grafana* -> grafana
resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 40

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
