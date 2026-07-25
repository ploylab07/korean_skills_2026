# unicorn-kms-app : Secrets Manager / DynamoDB
resource "aws_kms_key" "app" {
  description             = "unicorn-kms-app - Secrets Manager / DynamoDB"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowDynamoDB"
        Effect    = "Allow"
        Principal = { Service = "dynamodb.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "dynamodb.${local.region}.amazonaws.com" }
        }
      },
      {
        Sid       = "AllowSecretsManager"
        Effect    = "Allow"
        Principal = { Service = "secretsmanager.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com" }
        }
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "unicorn-kms-app" })
}

resource "aws_kms_alias" "app" {
  name          = "alias/unicorn-kms-app"
  target_key_id = aws_kms_key.app.key_id
}

# unicorn-kms-data : S3 / ECR
resource "aws_kms_key" "data" {
  description             = "unicorn-kms-data - S3 / ECR"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowS3"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
      {
        Sid       = "AllowECR"
        Effect    = "Allow"
        Principal = { Service = "ecr.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "ecr.${local.region}.amazonaws.com" }
        }
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "unicorn-kms-data" })
}

resource "aws_kms_alias" "data" {
  name          = "alias/unicorn-kms-data"
  target_key_id = aws_kms_key.data.key_id
}

# unicorn-kms-platform : multi-region primary (us-east-1) — EKS secrets / EBS / CloudWatch+WAF logs
resource "aws_kms_key" "platform_primary" {
  provider                = aws.us_east_1
  description             = "unicorn-kms-platform - EKS secrets / EBS / logs (primary, multi-region)"
  deletion_window_in_days = 7
  multi_region            = true
  enable_key_rotation     = true
  rotation_period_in_days = 90

  # Baseline: root admin only. Service grants are added per-region via
  # aws_kms_key_policy so replica callers (ap-northeast-2 EKS/EC2/Logs) work too.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "unicorn-kms-platform" })
}

resource "aws_kms_alias" "platform_primary" {
  provider      = aws.us_east_1
  name          = "alias/unicorn-kms-platform"
  target_key_id = aws_kms_key.platform_primary.key_id
}

# WAF (CloudFront scope) + its CloudWatch log group both live in us-east-1
resource "aws_kms_key_policy" "platform_primary" {
  provider = aws.us_east_1
  key_id   = aws_kms_key.platform_primary.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogsUsEast1"
        Effect    = "Allow"
        Principal = { Service = "logs.us-east-1.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:us-east-1:${local.account_id}:log-group:aws-waf-logs-unicorn" }
        }
      }
    ]
  })
}

# unicorn-kms-platform replica in ap-northeast-2 — EKS envelope encryption, EBS, EKS/VPC-flow CloudWatch logs
resource "aws_kms_replica_key" "platform" {
  description             = "unicorn-kms-platform - EKS secrets / EBS / logs (replica, ap-northeast-2)"
  deletion_window_in_days = 7
  primary_key_arn         = aws_kms_key.platform_primary.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "unicorn-kms-platform" })
}

resource "aws_kms_alias" "platform_replica" {
  name          = "alias/unicorn-kms-platform"
  target_key_id = aws_kms_replica_key.platform.key_id
}

resource "aws_kms_key_policy" "platform_replica" {
  key_id = aws_kms_replica_key.platform.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowEKS"
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "eks.${local.region}.amazonaws.com" }
        }
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*" }
        }
      },
      {
        # Required so EKS-managed node group Auto Scaling groups can launch
        # instances whose EBS volumes are encrypted with this CMK.
        Sid       = "AllowAutoScalingServiceLinkedRoleForEBS"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling" }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })
}
