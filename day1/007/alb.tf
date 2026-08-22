locals {
  # Shared secret CloudFront injects as a custom origin header so the ALB can
  # refuse any request that didn't come through unicorn-svc-cf.
  origin_verify_header = "X-Origin-Verify"
  origin_verify_value  = "unicorn-svc-cf-${local.account_id}"
}

resource "aws_security_group" "alb" {
  name        = "unicorn-alb-sg"
  description = "Internal ALB for unicorn-svc-cf VPC origin"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "VPC CIDR (CloudFront VPC origin ENIs)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # Required for CloudFront VPC Origin reachability (CIDR alone times out).
  ingress {
    description     = "CloudFront origin-facing prefix list"
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

  tags = merge(local.common_tags, { Name = "unicorn-alb-sg" })
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "grafana_alb" {
  name        = "unicorn-grafana-alb-sg"
  description = "Internet-facing ALB for Grafana"
  vpc_id      = aws_vpc.main.id

  ingress {
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

  tags = merge(local.common_tags, { Name = "unicorn-grafana-alb-sg" })
}

resource "aws_lb" "book" {
  name               = "unicorn-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.private : s.id]

  tags = merge(local.common_tags, { Name = "unicorn-alb" })
}

resource "aws_lb_target_group" "book" {
  name        = "unicorn-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = merge(local.common_tags, { Name = "unicorn-tg" })
}

resource "aws_lb_target_group" "lambda" {
  name        = "unicorn-lambda-tg"
  target_type = "lambda"

  tags = merge(local.common_tags, { Name = "unicorn-lambda-tg" })
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.get_booking.arn
  depends_on       = [aws_lambda_permission.alb]
}

resource "aws_lb_listener" "book" {
  load_balancer_arn = aws_lb.book.arn
  port              = 80
  protocol          = "HTTP"

  # Anything that skips CloudFront (no origin-verify header) is rejected.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

# POST /v1/book -> Book App
resource "aws_lb_listener_rule" "book_post" {
  listener_arn = aws_lb_listener.book.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    http_header {
      http_header_name = local.origin_verify_header
      values           = [local.origin_verify_value]
    }
  }

  condition {
    http_request_method {
      values = ["POST"]
    }
  }

  condition {
    path_pattern {
      values = ["/v1/book"]
    }
  }
}

# GET /v1/book -> Lambda (booking lookup)
resource "aws_lb_listener_rule" "book_get" {
  listener_arn = aws_lb_listener.book.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    http_header {
      http_header_name = local.origin_verify_header
      values           = [local.origin_verify_value]
    }
  }

  condition {
    http_request_method {
      values = ["GET"]
    }
  }

  condition {
    path_pattern {
      values = ["/v1/book"]
    }
  }
}

# GET /health -> Book App
resource "aws_lb_listener_rule" "health" {
  listener_arn = aws_lb_listener.book.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    http_header {
      http_header_name = local.origin_verify_header
      values           = [local.origin_verify_value]
    }
  }

  condition {
    http_request_method {
      values = ["GET"]
    }
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

# --- Grafana (internet-facing) ---
resource "aws_lb" "grafana" {
  name               = "unicorn-grafana-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.grafana_alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = merge(local.common_tags, { Name = "unicorn-grafana-alb" })
}

resource "aws_lb_target_group" "grafana" {
  name        = "unicorn-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled  = true
    path     = "/api/health"
    matcher  = "200"
    interval = 30
  }

  tags = merge(local.common_tags, { Name = "unicorn-grafana-tg" })
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
