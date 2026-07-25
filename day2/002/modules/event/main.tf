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

  required_version = ">= 1.5.0"
}

data "aws_caller_identity" "current" {
  provider = aws
}

data "aws_ssm_parameter" "amazon_linux_ami" {
  provider = aws
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  common_tags = {
    Project     = "wsc2026"
    Environment = "production"
  }
  config_bucket_name = "wsc2026-event-config-${data.aws_caller_identity.current.account_id}"
  trail_bucket_name  = "wsc2026-event-trail-${data.aws_caller_identity.current.account_id}"
  lambda_source      = abspath("${path.module}/../../module3/lambda-function.py")
}

resource "aws_vpc" "event" {
  provider             = aws
  cidr_block           = "172.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "event-vpc" })
}

resource "aws_subnet" "public_a" {
  provider                = aws
  vpc_id                  = aws_vpc.event.id
  cidr_block              = "172.16.0.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "event-pub-a" })
}

resource "aws_subnet" "public_b" {
  provider                = aws
  vpc_id                  = aws_vpc.event.id
  cidr_block              = "172.16.1.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "event-pub-b" })
}

resource "aws_internet_gateway" "event" {
  provider = aws
  vpc_id   = aws_vpc.event.id

  tags = merge(local.common_tags, { Name = "event-igw" })
}

resource "aws_route_table" "public" {
  provider = aws
  vpc_id   = aws_vpc.event.id

  tags = merge(local.common_tags, { Name = "event-pub-rtb" })
}

resource "aws_route" "internet" {
  provider               = aws
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.event.id
}

resource "aws_route_table_association" "public_a" {
  provider       = aws
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  provider       = aws
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  provider           = aws
  name               = "wsc2026-event-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  provider   = aws
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  provider = aws
  name     = aws_iam_role.ec2.name
  role     = aws_iam_role.ec2.name
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  provider           = aws
  name               = "wsc2026-event-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy" "lambda" {
  provider = aws
  name     = "wsc2026-event-lambda-policy"
  role     = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:StartInstances",
          "ec2:StopInstances",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alert.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_security_group" "event" {
  provider    = aws
  name        = "wsc2026-event-sg"
  description = "No inbound access; monitored by event remediation"
  vpc_id      = aws_vpc.event.id

  # No ingress blocks: the group intentionally begins with zero inbound rules.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "wsc2026-event-sg" })
}

resource "aws_instance" "event" {
  provider                    = aws
  ami                         = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.event.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name        = "wsc2026-event-ec2"
    Environment = "production"
  })
}

# Intentionally missing required tags for mark2-3 Config NON_COMPLIANT check
resource "aws_instance" "tag_noncompliant" {
  provider                    = aws
  ami                         = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.event.id]
  associate_public_ip_address = true
}

resource "aws_sns_topic" "alert" {
  provider = aws
  name     = "wsc2026-event-alert"
  tags     = local.common_tags
}

data "archive_file" "stop_remediation" {
  type        = "zip"
  output_path = "${path.module}/wsc2026-ec2-stop-remediation.zip"
  source {
    content  = file(local.lambda_source)
    filename = "index.py"
  }
}

data "archive_file" "terminate_alert" {
  type        = "zip"
  output_path = "${path.module}/wsc2026-ec2-terminate-alert.zip"
  source {
    content  = file(local.lambda_source)
    filename = "index.py"
  }
}

data "archive_file" "sg_remediation" {
  type        = "zip"
  output_path = "${path.module}/wsc2026-sg-remediation.zip"
  source {
    content  = file(local.lambda_source)
    filename = "index.py"
  }
}

data "archive_file" "tag_alert" {
  type        = "zip"
  output_path = "${path.module}/wsc2026-tag-alert.zip"
  source {
    content  = file(local.lambda_source)
    filename = "index.py"
  }
}

resource "aws_lambda_function" "stop_remediation" {
  provider         = aws
  function_name    = "wsc2026-ec2-stop-remediation"
  role             = aws_iam_role.lambda.arn
  handler          = "index.ec2_stop_remediation_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.stop_remediation.output_path
  source_code_hash = data.archive_file.stop_remediation.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      INSTANCE_ID   = aws_instance.event.id
      SNS_TOPIC_ARN = aws_sns_topic.alert.arn
    }
  }

  depends_on = [aws_iam_role_policy.lambda]
}

resource "aws_lambda_function" "terminate_alert" {
  provider         = aws
  function_name    = "wsc2026-ec2-terminate-alert"
  role             = aws_iam_role.lambda.arn
  handler          = "index.ec2_terminate_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.terminate_alert.output_path
  source_code_hash = data.archive_file.terminate_alert.output_base64sha256
  timeout          = 30

  environment {
    variables = { SNS_TOPIC_ARN = aws_sns_topic.alert.arn }
  }

  depends_on = [aws_iam_role_policy.lambda]
}

resource "aws_lambda_function" "sg_remediation" {
  provider         = aws
  function_name    = "wsc2026-sg-remediation"
  role             = aws_iam_role.lambda.arn
  handler          = "index.sg_remediation_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.sg_remediation.output_path
  source_code_hash = data.archive_file.sg_remediation.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SECURITY_GROUP_ID = aws_security_group.event.id
      SNS_TOPIC_ARN     = aws_sns_topic.alert.arn
    }
  }

  depends_on = [aws_iam_role_policy.lambda]
}

resource "aws_lambda_function" "tag_alert" {
  provider         = aws
  function_name    = "wsc2026-tag-alert"
  role             = aws_iam_role.lambda.arn
  handler          = "index.tag_alert_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.tag_alert.output_path
  source_code_hash = data.archive_file.tag_alert.output_base64sha256
  timeout          = 30

  environment {
    variables = { SNS_TOPIC_ARN = aws_sns_topic.alert.arn }
  }

  depends_on = [aws_iam_role_policy.lambda]
}

resource "aws_cloudwatch_event_rule" "ec2_stop" {
  provider = aws
  name     = "wsc2026-ec2-stop-rule"
  state    = "ENABLED"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail        = { state = ["stopped"] }
  })
}

resource "aws_cloudwatch_event_rule" "ec2_terminate" {
  provider = aws
  name     = "wsc2026-ec2-terminate-rule"
  state    = "ENABLED"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail        = { state = ["terminated"] }
  })
}

resource "aws_cloudwatch_event_rule" "sg_change" {
  provider = aws
  name     = "wsc2026-sg-change-rule"
  state    = "ENABLED"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["AuthorizeSecurityGroupIngress"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ec2_stop" {
  provider = aws
  rule     = aws_cloudwatch_event_rule.ec2_stop.name
  target_id = "stop-remediation"
  arn      = aws_lambda_function.stop_remediation.arn
}

resource "aws_cloudwatch_event_target" "ec2_terminate" {
  provider = aws
  rule     = aws_cloudwatch_event_rule.ec2_terminate.name
  target_id = "terminate-alert"
  arn      = aws_lambda_function.terminate_alert.arn
}

resource "aws_cloudwatch_event_target" "sg_change" {
  provider = aws
  rule     = aws_cloudwatch_event_rule.sg_change.name
  target_id = "sg-remediation"
  arn      = aws_lambda_function.sg_remediation.arn
}

resource "aws_lambda_permission" "ec2_stop" {
  provider      = aws
  statement_id  = "allow-eventbridge-stop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_stop.arn
}

resource "aws_lambda_permission" "ec2_terminate" {
  provider      = aws
  statement_id  = "allow-eventbridge-terminate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terminate_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_terminate.arn
}

resource "aws_lambda_permission" "sg_change" {
  provider      = aws
  statement_id  = "allow-eventbridge-sg-change"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sg_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sg_change.arn
}

resource "aws_s3_bucket" "config" {
  provider      = aws
  bucket        = local.config_bucket_name
  force_destroy = var.force_destroy
  tags          = local.common_tags
}

resource "aws_s3_bucket_policy" "config" {
  provider = aws
  bucket   = aws_s3_bucket.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.config.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "config_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  provider           = aws
  name               = "wsc2026-event-config-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json
}

resource "aws_iam_role_policy_attachment" "config" {
  provider   = aws
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "event" {
  provider = aws
  name     = "wsc2026-event-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "event" {
  provider       = aws
  name           = "wsc2026-event-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config.bucket

  depends_on = [aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "event" {
  provider   = aws
  name       = aws_config_configuration_recorder.event.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.event, aws_iam_role_policy_attachment.config]
}

resource "aws_config_config_rule" "restricted_ssh" {
  provider = aws
  name     = "wsc2026-sg-ssh-rule"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  scope {
    compliance_resource_types = ["AWS::EC2::SecurityGroup"]
  }

  depends_on = [aws_config_configuration_recorder_status.event]
}

resource "aws_config_config_rule" "required_tags" {
  provider = aws
  name     = "wsc2026-required-tags-rule"
  input_parameters = jsonencode({
    tag1Key = "Name"
    tag2Key = "Environment"
  })

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }

  depends_on = [aws_config_configuration_recorder_status.event]
}

resource "aws_cloudwatch_event_rule" "tag_noncompliance" {
  provider = aws
  name     = "wsc2026-tag-alert-rule"
  state    = "ENABLED"
  event_pattern = jsonencode({
    source        = ["aws.config"]
    "detail-type" = ["Config Rules Compliance Change"]
    detail = {
      configRuleName = [aws_config_config_rule.required_tags.name]
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "tag_noncompliance" {
  provider  = aws
  rule      = aws_cloudwatch_event_rule.tag_noncompliance.name
  target_id = "tag-alert"
  arn       = aws_lambda_function.tag_alert.arn
}

resource "aws_lambda_permission" "tag_noncompliance" {
  provider      = aws
  statement_id  = "allow-eventbridge-tag-alert"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tag_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.tag_noncompliance.arn
}

resource "aws_s3_bucket" "trail" {
  provider      = aws
  bucket        = local.trail_bucket_name
  force_destroy = var.force_destroy
  tags          = local.common_tags
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  provider = aws
  bucket   = aws_s3_bucket.trail.id
  policy   = data.aws_iam_policy_document.trail_bucket.json
}

resource "aws_cloudtrail" "event" {
  provider                      = aws
  name                          = "wsc2026-event-trail"
  s3_bucket_name                = aws_s3_bucket.trail.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.trail]
}
