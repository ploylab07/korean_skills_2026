terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws]
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

data "aws_availability_zones" "available" {
  provider = aws
  state    = "available"
}

data "aws_ssm_parameter" "al2023_ami" {
  provider = aws
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_vpc" "analytics" {
  provider = aws
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "analytics-vpc" }
}

resource "aws_subnet" "public_a" {
  provider = aws
  vpc_id                  = aws_vpc.analytics.id
  cidr_block              = "10.20.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "analytics-pub-a" }
}

resource "aws_subnet" "public_b" {
  provider = aws
  vpc_id                  = aws_vpc.analytics.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = { Name = "analytics-pub-b" }
}

resource "aws_subnet" "private_a" {
  provider = aws
  vpc_id            = aws_vpc.analytics.id
  cidr_block        = "10.20.100.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "analytics-priv-a" }
}

resource "aws_subnet" "private_b" {
  provider = aws
  vpc_id            = aws_vpc.analytics.id
  cidr_block        = "10.20.101.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "analytics-priv-b" }
}

resource "aws_internet_gateway" "analytics" {
  provider = aws
  vpc_id = aws_vpc.analytics.id

  tags = { Name = "analytics-igw" }
}

resource "aws_route_table" "public" {
  provider = aws
  vpc_id = aws_vpc.analytics.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.analytics.id
  }

  tags = { Name = "analytics-pub-rtb" }
}

resource "aws_route_table_association" "public_a" {
  provider = aws
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  provider = aws
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  provider = aws
  domain   = "vpc"

  tags = { Name = "analytics-ngw-eip" }
}

resource "aws_nat_gateway" "analytics" {
  provider      = aws
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  depends_on = [aws_internet_gateway.analytics]

  tags = { Name = "analytics-ngw" }
}

resource "aws_route_table" "private_a" {
  provider = aws
  vpc_id   = aws_vpc.analytics.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.analytics.id
  }

  tags = { Name = "analytics-priv-a-rtb" }
}

resource "aws_route_table" "private_b" {
  provider = aws
  vpc_id   = aws_vpc.analytics.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.analytics.id
  }

  tags = { Name = "analytics-priv-b-rtb" }
}

resource "aws_route_table_association" "private_a" {
  provider = aws
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_b" {
  provider = aws
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

resource "aws_kinesis_stream" "orders" {
  provider         = aws
  name             = "wsc2026-order-stream"
  retention_period = 24

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
}

resource "aws_iam_role" "ec2" {
  provider = aws
  name = "wsc2026-alaytics-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  provider = aws
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_kinesis" {
  provider = aws
  name = "kinesis-write"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesis:PutRecord",
        "kinesis:PutRecords",
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary"
      ]
      Resource = aws_kinesis_stream.orders.arn
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  provider = aws
  name = aws_iam_role.ec2.name
  role = aws_iam_role.ec2.name
}

resource "aws_iam_role" "flink" {
  provider = aws
  name = "wsc2026-analytics-flink-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "kinesisanalytics.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flink" {
  provider = aws
  name     = "analytics-flink"
  role     = aws_iam_role.flink.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards",
          "kinesis:SubscribeToShard",
          "kinesis:ListStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateDatabase",
          "glue:CreateTable",
          "glue:GetTable",
          "glue:GetTables",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetPartitions",
          "glue:GetUserDefinedFunctions"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:*", "s3:*", "cloudwatch:*"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.flink.arn
      }
    ]
  })
}

resource "time_sleep" "flink_iam" {
  depends_on      = [aws_iam_role_policy.flink]
  create_duration = "20s"
}

resource "aws_security_group" "alb" {
  provider = aws
  name        = "wsc2026-analytics-alb-sg"
  description = "Public HTTP access to the analytics ALB"
  vpc_id      = aws_vpc.analytics.id

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

  tags = { Name = "wsc2026-analytics-alb-sg" }
}

resource "aws_security_group" "ec2" {
  provider = aws
  name        = "wsc2026-analytics-ec2-sg"
  description = "Analytics application access from ALB"
  vpc_id      = aws_vpc.analytics.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc2026-analytics-ec2-sg" }
}

resource "aws_instance" "analytics" {
  provider = aws
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  user_data              = templatefile("${path.module}/userdata.sh.tpl", {
    app_py_b64       = filebase64("${path.module}/../../module2/app.py")
    requirements_b64 = filebase64("${path.module}/../../module2/requirements.txt")
    region           = var.region
  })
  user_data_replace_on_change = true

  tags = { Name = "wsc2026-analytics-ec2" }
}

resource "aws_lb" "analytics" {
  provider = aws
  name               = "wsc2026-analytics-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = { Name = "wsc2026-analytics-alb" }
}

resource "aws_lb_target_group" "analytics" {
  provider = aws
  name        = "wsc2026-analytics-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.analytics.id
  target_type = "instance"

  health_check {
    path     = "/health"
    protocol = "HTTP"
  }

  tags = { Name = "wsc2026-analytics-tg" }
}

resource "aws_lb_target_group_attachment" "analytics" {
  provider = aws
  target_group_arn = aws_lb_target_group.analytics.arn
  target_id        = aws_instance.analytics.id
  port             = 5000
}

resource "aws_lb_listener" "http" {
  provider = aws
  load_balancer_arn = aws_lb.analytics.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.analytics.arn
  }
}

resource "aws_kinesisanalyticsv2_application" "flink" {
  provider               = aws
  name                   = "wsc2026-analytics-flink"
  runtime_environment    = "ZEPPELIN-FLINK-3_0"
  application_mode       = "INTERACTIVE"
  service_execution_role = aws_iam_role.flink.arn

  depends_on = [
    aws_iam_role_policy.flink,
    time_sleep.flink_iam
  ]
}
