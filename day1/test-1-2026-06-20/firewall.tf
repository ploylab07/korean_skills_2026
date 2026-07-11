resource "aws_cloudwatch_log_group" "firewall" {
  name              = "/gj2025/firewall"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_networkfirewall_rule_group" "main" {
  capacity = 100
  name     = "${local.name_prefix}-firewall-rule"
  type     = "STATEFUL"
  rule_group {
    rules_source {
      rules_string = <<-EOT
        pass ip ${local.hub_vpc_cidr} any -> any any (msg:"allow hub vpc"; sid:1;)
        pass ip any any -> ${local.hub_vpc_cidr} any (msg:"allow to hub vpc"; sid:2;)
        pass ip ${local.app_vpc_cidr} any -> ${local.hub_vpc_cidr} any (msg:"allow app to hub"; sid:3;)
        pass ip ${local.hub_vpc_cidr} any -> ${local.app_vpc_cidr} any (msg:"allow hub to app"; sid:4;)
        drop http ${local.app_vpc_cidr} any -> any any (msg:"deny app http outbound"; sid:10;)
        drop tls ${local.app_vpc_cidr} any -> any any (msg:"deny app https outbound"; sid:11;)
        pass ip any any -> any any (msg:"default allow"; sid:99;)
      EOT
    }
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [local.hub_vpc_cidr, local.app_vpc_cidr]
        }
      }
    }
  }
  tags = local.common_tags
}

resource "aws_networkfirewall_firewall_policy" "main" {
  name = "${local.name_prefix}-firewall-policy"
  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.main.arn
    }
  }
  tags = local.common_tags
}

resource "aws_networkfirewall_firewall" "main" {
  name                = "${local.name_prefix}-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = aws_vpc.hub.id

  subnet_mapping {
    subnet_id = aws_subnet.hub_firewall.id
  }

  tags = local.common_tags
}

resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.main.arn
  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }
  }
}

# App VPC egress: TGW -> Hub -> Firewall endpoint -> NAT -> IGW
resource "aws_route" "hub_private_a_firewall" {
  route_table_id         = aws_route_table.hub_private_a.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = one(aws_networkfirewall_firewall.main.firewall_status[0].sync_states[*].attachment[0].endpoint_id)
  depends_on             = [aws_networkfirewall_firewall.main]
}

resource "aws_route" "hub_private_b_firewall" {
  route_table_id         = aws_route_table.hub_private_b.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = one(aws_networkfirewall_firewall.main.firewall_status[0].sync_states[*].attachment[0].endpoint_id)
  depends_on             = [aws_networkfirewall_firewall.main]
}
