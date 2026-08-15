terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
      configuration_aliases = [aws]
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

data "aws_region" "current" {
  provider = aws
}

data "aws_caller_identity" "current" {
  provider = aws
}

data "aws_availability_zones" "available" {
  provider = aws
  state    = "available"
}

data "aws_ami" "amazon_linux" {
  provider    = aws
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

locals {
  name_prefix       = "wsc2026"
  raw_topic         = "${local.name_prefix}-sensor-raw"
  alert_topic       = "${local.name_prefix}-sensor-alert"
  bucket_name       = "${local.name_prefix}-sensor-alert-bucket-${var.participant_id}"
  private_subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_d.id]
}

resource "aws_vpc" "msk" {
  provider             = aws
  cidr_block           = "192.168.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "msk-vpc" }
}

resource "aws_subnet" "public_a" {
  provider                = aws
  vpc_id                  = aws_vpc.msk.id
  cidr_block              = "192.168.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "msk-pub-a" }
}

resource "aws_subnet" "public_d" {
  provider                = aws
  vpc_id                  = aws_vpc.msk.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = { Name = "msk-pub-d" }
}

resource "aws_subnet" "private_a" {
  provider          = aws
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "192.168.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "msk-priv-a" }
}

resource "aws_subnet" "private_d" {
  provider          = aws
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "192.168.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags              = { Name = "msk-priv-d" }
}

resource "aws_internet_gateway" "msk" {
  provider = aws
  vpc_id   = aws_vpc.msk.id
  tags     = { Name = "msk-igw" }
}

resource "aws_route_table" "public" {
  provider = aws
  vpc_id   = aws_vpc.msk.id
  tags     = { Name = "msk-pub-rtb" }
}

resource "aws_route" "public_internet" {
  provider               = aws
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.msk.id
}

resource "aws_route_table_association" "public" {
  provider       = aws
  for_each       = { a = aws_subnet.public_a.id, d = aws_subnet.public_d.id }
  subnet_id      = each.value
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  provider = aws
  domain   = "vpc"
  tags     = { Name = "msk-nat-eip" }
}

resource "aws_nat_gateway" "msk" {
  provider      = aws
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.msk]
  tags          = { Name = "msk-ngw" }
}

resource "aws_route_table" "private" {
  provider = aws
  for_each = { a = aws_subnet.private_a.id, d = aws_subnet.private_d.id }
  vpc_id   = aws_vpc.msk.id
  tags     = { Name = "msk-priv-${each.key}-rtb" }
}

resource "aws_route" "private_nat" {
  provider               = aws
  for_each               = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.msk.id
}

resource "aws_route_table_association" "private" {
  provider       = aws
  for_each       = { a = aws_subnet.private_a.id, d = aws_subnet.private_d.id }
  subnet_id      = each.value
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_s3_bucket" "alerts" {
  provider = aws
  bucket   = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "alerts" {
  provider                = aws
  bucket                  = aws_s3_bucket.alerts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "producer_binary" {
  provider = aws
  bucket   = aws_s3_bucket.alerts.id
  key      = "deploy/app"
  source   = "${path.module}/../../module4/app"
  etag     = filemd5("${path.module}/../../module4/app")
}

resource "aws_dynamodb_table" "sensor_data" {
  provider     = aws
  name         = "${local.name_prefix}-sensor-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sensorId"
  range_key    = "timestamp"

  attribute {
    name = "sensorId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}

resource "aws_sns_topic" "alerts" {
  provider = aws
  name     = local.alert_topic
}

resource "aws_security_group" "msk" {
  provider    = aws
  name        = "msk-sg"
  description = "MSK brokers"
  vpc_id      = aws_vpc.msk.id
  tags        = { Name = "msk-sg" }
}

resource "aws_security_group" "ec2" {
  provider    = aws
  name        = "msk-ec2-sg"
  description = "Sensor producer"
  vpc_id      = aws_vpc.msk.id
  tags        = { Name = "msk-ec2-sg" }
}

resource "aws_security_group" "lambda" {
  provider    = aws
  name        = "msk-lambda-sg"
  description = "MSK Lambda functions"
  vpc_id      = aws_vpc.msk.id
  tags        = { Name = "msk-lambda-sg" }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  provider = aws
  for_each = {
    msk    = aws_security_group.msk.id
    ec2    = aws_security_group.ec2.id
    lambda = aws_security_group.lambda.id
  }
  security_group_id = each.value
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "broker_ports" {
  provider = aws
  for_each = {
    msk    = aws_security_group.msk.id
    ec2    = aws_security_group.ec2.id
    lambda = aws_security_group.lambda.id
  }
  security_group_id            = aws_security_group.msk.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 9092
  to_port                      = 9098
}

resource "aws_iam_role" "ec2" {
  provider = aws
  name     = "${local.name_prefix}-msk-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  provider   = aws
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2" {
  provider = aws
  name     = "msk-ec2-inline"
  role     = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.alerts.arn}/deploy/*" },
      { Effect = "Allow", Action = ["kafka:DescribeCluster", "kafka:GetBootstrapBrokers", "ec2:Describe*"], Resource = "*" }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  provider = aws
  name     = aws_iam_role.ec2.name
  role     = aws_iam_role.ec2.name
}

resource "aws_iam_role" "lambda" {
  provider = aws
  name     = "${local.name_prefix}-msk-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  provider   = aws
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  provider   = aws
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_msk" {
  provider   = aws
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole"
}

resource "aws_iam_role_policy" "lambda" {
  provider = aws
  name     = "msk-lambda-inline"
  role     = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Scan", "dynamodb:Query"], Resource = aws_dynamodb_table.sensor_data.arn },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.alerts.arn },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = ["${aws_s3_bucket.alerts.arn}", "${aws_s3_bucket.alerts.arn}/*"] },
      {
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:DescribeClusterV2",
          "kafka:GetBootstrapBrokers",
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_msk_configuration" "cluster" {
  provider          = aws
  name              = "${local.name_prefix}-msk-configuration"
  kafka_versions    = ["3.6.0"]
  server_properties = <<-PROPERTIES
    auto.create.topics.enable=true
  PROPERTIES
}

resource "aws_msk_cluster" "this" {
  provider               = aws
  cluster_name           = "${local.name_prefix}-msk-cluster"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 2
  configuration_info {
    arn      = aws_msk_configuration.cluster.arn
    revision = aws_msk_configuration.cluster.latest_revision
  }

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = local.private_subnet_ids
    security_groups = [aws_security_group.msk.id]
    storage_info {
      ebs_storage_info {
        volume_size = 20
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
    unauthenticated = true
  }
}

resource "aws_msk_cluster_policy" "lambda" {
  provider     = aws
  cluster_arn  = aws_msk_cluster.this.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { AWS = aws_iam_role.lambda.arn }
      Action = [
        "kafka-cluster:Connect",
        "kafka-cluster:DescribeCluster",
        "kafka-cluster:DescribeClusterDynamicConfiguration",
        "kafka-cluster:DescribeGroup",
        "kafka-cluster:AlterGroup",
        "kafka-cluster:DescribeTopic",
        "kafka-cluster:ReadData",
        "kafka-cluster:WriteData",
      ]
      Resource = [
        aws_msk_cluster.this.arn,
        "arn:aws:kafka:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:topic/${aws_msk_cluster.this.cluster_name}/${element(split("/", aws_msk_cluster.this.arn), 2)}/*",
        "arn:aws:kafka:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:group/${aws_msk_cluster.this.cluster_name}/${element(split("/", aws_msk_cluster.this.arn), 2)}/*",
      ]
    }]
  })
}

resource "terraform_data" "sensor_consumer_package" {
  triggers_replace = [
    filesha256("${path.module}/lambda/sensor-consumer/index.py"),
    filesha256("${path.module}/lambda/sensor-consumer/requirements.txt"),
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      package_dir="${path.module}/.build/sensor-consumer"
      rm -rf "$package_dir"
      mkdir -p "$package_dir"
      cp "${path.module}/lambda/sensor-consumer/index.py" "$package_dir/index.py"
      python3 -m pip install --disable-pip-version-check --break-system-packages --target "$package_dir" -r "${path.module}/lambda/sensor-consumer/requirements.txt"
    EOT
  }
}

data "archive_file" "sensor_consumer" {
  type        = "zip"
  source_dir  = "${path.module}/.build/sensor-consumer"
  output_path = "${path.module}/.build/sensor-consumer.zip"
  depends_on  = [terraform_data.sensor_consumer_package]
}

data "archive_file" "alert_consumer" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/alert-consumer"
  output_path = "${path.module}/.build/alert-consumer.zip"
}

resource "aws_lambda_function" "sensor_consumer" {
  provider         = aws
  function_name    = "${local.name_prefix}-sensor-consumer"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.14"
  filename         = data.archive_file.sensor_consumer.output_path
  source_code_hash = data.archive_file.sensor_consumer.output_base64sha256
  timeout          = 60
  memory_size      = 256
  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }
  environment {
    variables = {
      DDB_TABLE        = aws_dynamodb_table.sensor_data.name
      ALERT_TOPIC      = local.alert_topic
      BOOTSTRAP_SERVER = aws_msk_cluster.this.bootstrap_brokers
    }
  }
}

resource "aws_lambda_function" "alert_consumer" {
  provider         = aws
  function_name    = "${local.name_prefix}-sensor-alert-consumer"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.14"
  filename         = data.archive_file.alert_consumer.output_path
  source_code_hash = data.archive_file.alert_consumer.output_base64sha256
  timeout          = 60
  memory_size      = 256
  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
      S3_BUCKET     = aws_s3_bucket.alerts.bucket
    }
  }
}

resource "aws_lambda_event_source_mapping" "raw" {
  provider         = aws
  event_source_arn = aws_msk_cluster.this.arn
  function_name    = aws_lambda_function.sensor_consumer.arn
  topics           = [local.raw_topic]
  starting_position = "LATEST"
  batch_size        = 10
  enabled           = true
}

resource "aws_lambda_event_source_mapping" "alerts" {
  provider         = aws
  event_source_arn = aws_msk_cluster.this.arn
  function_name    = aws_lambda_function.alert_consumer.arn
  topics           = [local.alert_topic]
  starting_position = "LATEST"
  batch_size        = 10
  enabled           = true
}

resource "aws_instance" "sensor_producer" {
  provider                    = aws
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = false
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    bucket    = aws_s3_bucket.alerts.bucket
    region    = data.aws_region.current.region
    bootstrap = aws_msk_cluster.this.bootstrap_brokers
  })
  depends_on = [aws_s3_object.producer_binary, aws_msk_cluster.this]
  tags       = { Name = "${local.name_prefix}-sensor-producer" }
}
