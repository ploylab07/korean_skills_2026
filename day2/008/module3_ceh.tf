############################################
# Module 3 — Cloud Event Handling (ap-southeast-1)
############################################

resource "aws_vpc" "ceh" {
  provider             = aws.singapore
  cidr_block           = "10.73.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "skills-ceh-vpc" })
}

resource "aws_internet_gateway" "ceh" {
  provider = aws.singapore
  vpc_id   = aws_vpc.ceh.id
  tags     = merge(local.common_tags, { Name = "skills-ceh-igw" })
}

resource "aws_subnet" "ceh" {
  provider                = aws.singapore
  vpc_id                  = aws_vpc.ceh.id
  cidr_block              = "10.73.1.0/24"
  availability_zone       = data.aws_availability_zones.singapore.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "skills-ceh-subnet" })
}

resource "aws_route_table" "ceh" {
  provider = aws.singapore
  vpc_id   = aws_vpc.ceh.id
  tags     = merge(local.common_tags, { Name = "skills-ceh-rt" })
}

resource "aws_route" "ceh_default" {
  provider               = aws.singapore
  route_table_id         = aws_route_table.ceh.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ceh.id
}

resource "aws_route_table_association" "ceh" {
  provider       = aws.singapore
  subnet_id      = aws_subnet.ceh.id
  route_table_id = aws_route_table.ceh.id
}

resource "aws_security_group" "ceh_protected" {
  provider    = aws.singapore
  name        = "skills-ceh-protected-sg"
  description = "protected"
  vpc_id      = aws_vpc.ceh.id
  tags        = merge(local.common_tags, { Name = "skills-ceh-protected-sg" })

  # no inbound rules (required)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ceh" {
  provider                    = aws.singapore
  ami                         = local.ami_singapore
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.ceh.id
  vpc_security_group_ids      = [aws_security_group.ceh_protected.id]
  associate_public_ip_address = true
  tags                        = merge(local.common_tags, { Name = "skills-ceh-ec2" })
}

resource "aws_sns_topic" "ceh" {
  provider = aws.singapore
  name     = "skills-ceh-alert-topic"
  tags     = merge(local.common_tags, { Name = "skills-ceh-alert-topic" })
}

resource "aws_iam_role" "ceh_lambda" {
  name = "skills-ceh-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ceh_lambda_basic" {
  role       = aws_iam_role.ceh_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ceh_lambda" {
  name = "skills-ceh-lambda-policy"
  role = aws_iam_role.ceh_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupIngress"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.ceh.arn
      }
    ]
  })
}

data "archive_file" "ceh_lambda" {
  type        = "zip"
  source_file = "${path.module}/모듈3_지급파일/remediate_security_group.py"
  output_path = "${path.module}/.generated/skills-ceh-lambda.zip"
}

resource "aws_lambda_function" "ceh" {
  provider         = aws.singapore
  function_name    = "skills-ceh-remediate-fn"
  role             = aws_iam_role.ceh_lambda.arn
  handler          = "remediate_security_group.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.ceh_lambda.output_path
  source_code_hash = data.archive_file.ceh_lambda.output_base64sha256

  environment {
    variables = {
      PROTECTED_SECURITY_GROUP_ID = aws_security_group.ceh_protected.id
      SNS_TOPIC_ARN               = aws_sns_topic.ceh.arn
    }
  }

  tags = merge(local.common_tags, { Name = "skills-ceh-remediate-fn" })
}

resource "aws_s3_bucket" "ceh_cloudtrail" {
  provider      = aws.singapore
  bucket        = "skills-ceh-cloudtrail-${local.account_id}-apse1"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_policy" "ceh_cloudtrail" {
  provider = aws.singapore
  bucket   = aws_s3_bucket.ceh_cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.ceh_cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.ceh_cloudtrail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "ceh" {
  provider                      = aws.singapore
  name                          = "skills-ceh-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.ceh_cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  depends_on                    = [aws_s3_bucket_policy.ceh_cloudtrail]
  tags                          = local.common_tags
}

resource "aws_cloudwatch_event_rule" "ceh_sg" {
  provider    = aws.singapore
  name        = "skills-ceh-sg-change-rule"
  description = "Detect AuthorizeSecurityGroupIngress"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["AuthorizeSecurityGroupIngress"]
    }
  })
  tags = merge(local.common_tags, { Name = "skills-ceh-sg-change-rule" })
}

resource "aws_cloudwatch_event_target" "ceh_lambda" {
  provider  = aws.singapore
  rule      = aws_cloudwatch_event_rule.ceh_sg.name
  target_id = "1"
  arn       = aws_lambda_function.ceh.arn
}

resource "aws_lambda_permission" "ceh_events" {
  provider      = aws.singapore
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ceh.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ceh_sg.arn
}
