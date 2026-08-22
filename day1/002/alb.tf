resource "aws_lb" "book" {
  name               = "wskorea26-book-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.pub_c.id, aws_subnet.pub_d.id]
  tags               = { Name = "wskorea26-book-alb" }
}

resource "aws_lb_target_group" "book" {
  name        = "wskorea26-book-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = "8080"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "wskorea26-book-tg" }
}

resource "aws_lb_target_group" "lambda" {
  name        = "wskorea26-lambda-tg"
  target_type = "lambda"
  tags        = { Name = "wskorea26-lambda-tg" }
}

resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.book.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.book.arn
  depends_on       = [aws_lambda_permission.alb]
}

resource "aws_lb_listener" "book" {
  load_balancer_arn = aws_lb.book.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "post_book" {
  listener_arn = aws_lb_listener.book.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = ["wskorea26-cf"]
    }
  }

  condition {
    http_request_method {
      values = ["POST"]
    }
  }

  condition {
    path_pattern {
      values = ["/book*", "/v1/book*"]
    }
  }
}

# RC marking 9-2/9-3: GET /reserv-query → Lambda (TP Reference03도 /book GET 허용)
resource "aws_lb_listener_rule" "get_book" {
  listener_arn = aws_lb_listener.book.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = ["wskorea26-cf"]
    }
  }

  condition {
    http_request_method {
      values = ["GET"]
    }
  }

  condition {
    path_pattern {
      values = ["/reserv-query*", "/book*"]
    }
  }
}

resource "aws_lb" "grafana" {
  name               = "wskorea26-grafana-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.grafana_alb.id]
  subnets            = [aws_subnet.pub_c.id, aws_subnet.pub_d.id]
  tags               = { Name = "wskorea26-grafana-alb" }
}

resource "aws_lb_target_group" "grafana" {
  name        = "wskorea26-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path    = "/api/health"
    matcher = "200"
  }

  tags = { Name = "wskorea26-grafana-tg" }
}

resource "aws_lb_listener" "grafana" {
  load_balancer_arn = aws_lb.grafana.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}
