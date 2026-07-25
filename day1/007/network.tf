resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "unicorn-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "unicorn-igw" })
}

# --- Public subnets (10.97.{0,1,2}.0/24) ---
resource "aws_subnet" "public" {
  for_each = { for idx, az in local.az_suffixes : az => idx }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.97.${each.value}.0/24"
  availability_zone       = "${local.region}${each.key}"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "unicorn-subnet-pub-${each.key}" })
}

# --- Private subnets (10.97.{10,11,12}.0/24) ---
resource "aws_subnet" "private" {
  for_each = { for idx, az in local.az_suffixes : az => idx + 10 }

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.97.${each.value}.0/24"
  availability_zone = "${local.region}${each.key}"

  tags = merge(local.common_tags, {
    Name = "unicorn-subnet-priv-${each.key}"
  })
}

# --- NAT (one per AZ, in the matching public subnet) ---
resource "aws_eip" "nat" {
  for_each = toset(local.az_suffixes)
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "unicorn-nat-eip-${each.key}" })
}

resource "aws_nat_gateway" "main" {
  for_each      = toset(local.az_suffixes)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(local.common_tags, { Name = "unicorn-nat-${each.key}" })
  depends_on    = [aws_internet_gateway.main]
}

# --- Route tables ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "unicorn-rt-pub" })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = toset(local.az_suffixes)
  vpc_id   = aws_vpc.main.id
  tags     = merge(local.common_tags, { Name = "unicorn-rt-priv-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each               = toset(local.az_suffixes)
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# --- VPC Flow Log -> CloudWatch Logs ---
resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/unicorn/vpc/flow-logs"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform.arn

  depends_on = [aws_kms_key_policy.platform_replica]
}

data "aws_iam_policy_document" "flow_log_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_log" {
  name               = "unicorn-vpc-flow-log-role"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "flow_log" {
  name = "unicorn-vpc-flow-log-policy"
  role = aws_iam_role.flow_log.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.flow_log.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn             = aws_iam_role.flow_log.arn
  max_aggregation_interval = 60

  tags = merge(local.common_tags, { Name = "unicorn-vpc-flow-log" })
}

# --- Security groups ---
resource "aws_security_group" "vpce" {
  name        = "unicorn-vpce-sg"
  description = "Interface VPC endpoints"
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

  tags = merge(local.common_tags, { Name = "unicorn-vpce-sg" })
}

resource "aws_security_group" "cluster" {
  name        = "unicorn-eks-cluster-sg"
  description = "EKS control plane ENIs"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "unicorn-eks-cluster-sg" })
}

# --- Gateway endpoints ---
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], [for rt in aws_route_table.private : rt.id])
  tags              = merge(local.common_tags, { Name = "unicorn-vpce-s3" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${local.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], [for rt in aws_route_table.private : rt.id])
  tags              = merge(local.common_tags, { Name = "unicorn-vpce-dynamodb" })
}

# --- Interface endpoints (private subnets only, App tier stays off the internet) ---
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
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  tags                = merge(local.common_tags, { Name = "unicorn-vpce-${each.value}" })
}
