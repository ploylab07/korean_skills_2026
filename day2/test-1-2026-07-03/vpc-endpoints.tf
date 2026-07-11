resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.prefix}-vpce-sg"
  description = "VPC endpoint security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-vpce-sg" })
}

locals {
  vpce_subnets = [aws_subnet.workload_a.id, aws_subnet.workload_c.id]
  vpce_services = [
    "ec2", "eks", "sts", "ecr.api", "ecr.dkr", "logs",
    "secretsmanager", "elasticloadbalancing", "kms",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.vpce_services)

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.vpce_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.common_tags, { Name = "${local.prefix}-vpce-${replace(each.key, ".", "-")}" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_c.id,
  ]
  tags = merge(local.common_tags, { Name = "${local.prefix}-vpce-s3" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_c.id,
  ]
  tags = merge(local.common_tags, { Name = "${local.prefix}-vpce-dynamodb" })
}
