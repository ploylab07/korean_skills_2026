terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws]
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
}

locals {
  app_py = file("${path.module}/../../Cloud event handling/app.py")
}

resource "aws_vpc" "event" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "gj2026-event-vpc" }
}

resource "aws_internet_gateway" "event" {
  vpc_id = aws_vpc.event.id

  tags = { Name = "gj2026-event-igw" }
}

resource "aws_subnet" "event" {
  vpc_id                  = aws_vpc.event.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = { Name = "gj2026-event-subnet" }
}

resource "aws_route_table" "event" {
  vpc_id = aws_vpc.event.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.event.id
  }

  tags = { Name = "gj2026-event-rt" }
}

resource "aws_route_table_association" "event" {
  subnet_id      = aws_subnet.event.id
  route_table_id = aws_route_table.event.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_key_pair" "event" {
  key_name   = "gj2026-event-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "event" {
  name        = "gj2026-event-sg"
  description = "GJ2026 event EC2"
  vpc_id      = aws_vpc.event.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "gj2026-event-sg" }
}

resource "aws_iam_role" "event_ec2" {
  name = "gj2026-event-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "event_ec2_ssm" {
  role       = aws_iam_role.event_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "event_ec2_cw" {
  role       = aws_iam_role.event_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "event_ec2_logs" {
  name = "gj2026-event-ec2-logs"
  role = aws_iam_role.event_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:FilterLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:DescribeAlarms", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics", "cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.app_py.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "event_ec2" {
  name = "gj2026-event-ec2-profile"
  role = aws_iam_role.event_ec2.name
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/gj2026/event/app-logs"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "recovery" {
  name              = "/gj2026/event/recovery"
  retention_in_days = 7
}

resource "aws_ssm_parameter" "app_py" {
  name  = "/gj2026/event/app-py"
  type  = "String"
  value = local.app_py
}

resource "aws_instance" "event" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.event.id
  vpc_security_group_ids      = [aws_security_group.event.id]
  iam_instance_profile        = aws_iam_instance_profile.event_ec2.name
  key_name                    = aws_key_pair.event.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data_base64 = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    app_py_b64 = base64encode(local.app_py)
  }))

  tags = { Name = "gj2026-event-ec2" }

  depends_on = [aws_cloudwatch_log_group.app]
}

resource "aws_cloudwatch_log_metric_filter" "health" {
  name           = "gj2026-event-health-filter"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "health"

  metric_transformation {
    name      = "health_log_count"
    namespace = "GJ2026/Event"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "app" {
  alarm_name          = "gj2026-event-app-alarm"
  comparison_operator = "LessThanThreshold"
  metric_name         = "app_process_count"
  namespace           = "procstat"
  period              = 10
  statistic           = "Minimum"
  threshold           = 1
  datapoints_to_alarm = 2
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"
  alarm_description   = "gj2026-app health metric"

  dimensions = {
    InstanceId = aws_instance.event.id
  }
}

data "archive_file" "updater" {
  type        = "zip"
  output_path = "${path.module}/.build/updater.zip"
  source {
    content  = file("${path.module}/lambda/updater.py")
    filename = "updater.py"
  }
}

data "archive_file" "recovery" {
  type        = "zip"
  output_path = "${path.module}/.build/recovery.zip"
  source {
    content  = file("${path.module}/lambda/recovery.py")
    filename = "recovery.py"
  }
}

resource "aws_iam_role" "lambda" {
  name = "gj2026-event-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "gj2026-event-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "updater" {
  function_name = "gj2026-event-updater"
  role          = aws_iam_role.lambda.arn
  handler       = "updater.handler"
  runtime       = "python3.14"
  timeout       = 120

  filename         = data.archive_file.updater.output_path
  source_code_hash = data.archive_file.updater.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID  = aws_instance.event.id
      PARAM_NAME   = aws_ssm_parameter.app_py.name
      LOG_GROUP    = aws_cloudwatch_log_group.recovery.name
      SERVICE_NAME = "gj2026-app"
    }
  }
}

resource "aws_lambda_function" "recovery" {
  function_name = "gj2026-event-recovery"
  role          = aws_iam_role.lambda.arn
  handler       = "recovery.handler"
  runtime       = "python3.14"
  timeout       = 300

  filename         = data.archive_file.recovery.output_path
  source_code_hash = data.archive_file.recovery.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID  = aws_instance.event.id
      PARAM_NAME   = aws_ssm_parameter.app_py.name
      LOG_GROUP    = aws_cloudwatch_log_group.recovery.name
      SERVICE_NAME = "gj2026-app"
    }
  }
}

resource "aws_cloudwatch_event_rule" "alarm" {
  name        = "gj2026-event-trigger-alarm"
  description = "Trigger recovery on app alarm"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.app.alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "recovery" {
  rule      = aws_cloudwatch_event_rule.alarm.name
  target_id = "recovery"
  arn       = aws_lambda_function.recovery.arn
}

resource "aws_lambda_permission" "recovery" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recovery.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.alarm.arn
}

resource "aws_cloudwatch_event_rule" "updater" {
  name                = "gj2026-event-updater-schedule"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "updater" {
  rule      = aws_cloudwatch_event_rule.updater.name
  target_id = "updater"
  arn       = aws_lambda_function.updater.arn
}

resource "aws_lambda_permission" "updater" {
  statement_id  = "AllowEventBridgeUpdater"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.updater.arn
}
