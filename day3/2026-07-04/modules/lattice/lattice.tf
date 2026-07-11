resource "aws_vpclattice_service_network" "main" {
  name = "wsc-app-service-network"
  auth_type = "NONE"
}

resource "aws_vpclattice_service" "main" {
  name = "wsc-app-service"
  auth_type = "NONE"
}

resource "aws_vpclattice_service_network_service_association" "main" {
  service_network_identifier = aws_vpclattice_service_network.main.id
  service_identifier         = aws_vpclattice_service.main.id
}

resource "aws_vpclattice_service_network_vpc_association" "hub" {
  service_network_identifier = aws_vpclattice_service_network.main.id
  vpc_identifier             = aws_vpc.hub.id
}

resource "aws_vpclattice_service_network_vpc_association" "spoke" {
  service_network_identifier = aws_vpclattice_service_network.main.id
  vpc_identifier             = aws_vpc.spoke.id
}

resource "aws_vpclattice_target_group" "v1" {
  name = "wsc-spoke-v1-tg"
  type = "ALB"

  config {
    vpc_identifier = aws_vpc.spoke.id
    port           = 80
    protocol       = "HTTP"
  }
}

resource "aws_vpclattice_target_group" "v2" {
  name = "wsc-spoke-v2-tg"
  type = "ALB"

  config {
    vpc_identifier = aws_vpc.spoke.id
    port           = 80
    protocol       = "HTTP"
  }
}

resource "aws_vpclattice_target_group_attachment" "v1" {
  target_group_identifier = aws_vpclattice_target_group.v1.id
  target {
    id   = aws_lb.app.arn
    port = 80
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpclattice_target_group_attachment" "v2" {
  target_group_identifier = aws_vpclattice_target_group.v2.id
  target {
    id   = aws_lb.app.arn
    port = 80
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpclattice_listener" "main" {
  name               = "wsc-app-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.main.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.v1.arn
        weight                  = 90
      }
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.v2.arn
        weight                  = 10
      }
    }
  }
}

resource "aws_vpclattice_listener_rule" "v1_header" {
  name               = "wsc-v1-header-rule"
  service_identifier = aws_vpclattice_service.main.id
  listener_identifier = aws_vpclattice_listener.main.arn
  priority           = 10

  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.v1.arn
        weight                  = 100
      }
    }
  }

  match {
    http_match {
      header_matches {
        name  = "version"
        match {
          exact = "v1"
        }
      }
    }
  }
}

resource "aws_vpclattice_listener_rule" "v2_header" {
  name               = "wsc-v2-header-rule"
  service_identifier = aws_vpclattice_service.main.id
  listener_identifier = aws_vpclattice_listener.main.arn
  priority           = 20

  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.v2.arn
        weight                  = 100
      }
    }
  }

  match {
    http_match {
      header_matches {
        name  = "version"
        match {
          exact = "v2"
        }
      }
    }
  }
}
