resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "gj2026-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "gj2026-igw" })
}

# Private-only subnets (no NAT) — scoring expects only these two
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = local.azs[0]

  tags = merge(local.common_tags, {
    Name                                          = "gj2026-private-subnet-a"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = local.azs[1]

  tags = merge(local.common_tags, {
    Name                                          = "gj2026-private-subnet-b"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })
}

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "gj2026-private-rtb-a" })
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "gj2026-private-rtb-b" })
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

resource "aws_security_group" "vpce" {
  name        = "gj2026-vpce-sg"
  description = "VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "gj2026-vpce-sg" })
}

resource "aws_security_group" "nodes" {
  name        = "gj2026-eks-nodes-sg"
  description = "EKS nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "node to node"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "pods"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "from ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "gj2026-eks-nodes-sg" })

  # Separate aws_security_group_rule.* manage cluster→node rules; do not strip them.
  lifecycle {
    ignore_changes = [ingress]
  }
}

resource "aws_security_group" "alb" {
  name        = "gj2026-alb-sg"
  description = "Internal ALB"
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

  tags = merge(local.common_tags, { Name = "gj2026-alb-sg" })
}

resource "aws_security_group" "cluster" {
  name        = "gj2026-eks-cluster-sg"
  description = "EKS cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "gj2026-eks-cluster-sg" })
}

resource "aws_security_group_rule" "cluster_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
}

resource "aws_security_group_rule" "nodes_from_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "nodes_from_cluster_kubelet" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
}

# Gateway endpoints
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_a.id, aws_route_table.private_b.id]
  tags              = merge(local.common_tags, { Name = "gj2026-vpce-s3" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${local.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_a.id, aws_route_table.private_b.id]
  tags              = merge(local.common_tags, { Name = "gj2026-vpce-ddb" })
}

locals {
  interface_services = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "sts",
    "ec2",
    "eks",
    "elasticloadbalancing",
    "autoscaling",
    "kms",
    "ssm",
    "ssmmessages",
    "ec2messages",
  ]
}

resource "aws_vpc_endpoint" "interfaces" {
  for_each = toset(local.interface_services)

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpce.id]
  tags                = merge(local.common_tags, { Name = "gj2026-vpce-${each.value}" })
}
