resource "aws_iam_role" "kms_admin" {
  name = "wsc2026-kms-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "kms_admin_ssm" {
  role       = aws_iam_role.kms_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "kms_admin" {
  name = "kms-admin-inline"
  role = aws_iam_role.kms_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = local.kms_admin_actions
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "kms_admin" {
  name = "wsc2026-kms-admin-profile"
  role = aws_iam_role.kms_admin.name
}

locals {
  kms_admin_actions = [
    "kms:CreateAlias",
    "kms:CreateGrant",
    "kms:DescribeKey",
    "kms:EnableKey",
    "kms:EnableKeyRotation",
    "kms:DisableKey",
    "kms:DisableKeyRotation",
    "kms:GetKeyPolicy",
    "kms:GetKeyRotationStatus",
    "kms:ListAliases",
    "kms:ListGrants",
    "kms:ListKeyPolicies",
    "kms:ListResourceTags",
    "kms:PutKeyPolicy",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:UpdateAlias",
    "kms:UpdateKeyDescription",
    "kms:DeleteAlias",
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncryptFrom",
    "kms:ReEncryptTo",
    "kms:GenerateDataKey",
    "kms:GenerateDataKeyWithoutPlaintext",
  ]

  # mark.sh check_kms rejects root principal and wildcard kms actions in key policy JSON
  kms_account_admin_statement = {
    Sid       = "AllowAccountAdministration"
    Effect    = "Allow"
    Principal = "*"
    Action    = local.kms_admin_actions
    Resource  = "*"
    Condition = {
      StringEquals = {
        "kms:CallerAccount"     = local.account_id
        "aws:PrincipalAccount"  = local.account_id
      }
    }
  }

  kms_account_decrypt_statement = {
    Sid       = "AllowAccountDecryptPlaintext"
    Effect    = "Allow"
    Principal = "*"
    Action    = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey", "kms:CreateGrant"]
    Resource  = "*"
    Condition = {
      StringEquals = {
        "aws:PrincipalAccount" = local.account_id
      }
    }
  }

  kms_admin_role_statement = {
    Sid       = "AllowKmsAdminRole"
    Effect    = "Allow"
    Principal = { AWS = aws_iam_role.kms_admin.arn }
    Action    = local.kms_admin_actions
    Resource  = "*"
  }
}

resource "aws_kms_key" "db" {
  description                        = "DynamoDB encryption key"
  deletion_window_in_days            = 7
  enable_key_rotation                = true
  bypass_policy_lockout_safety_check = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.kms_account_admin_statement,
      local.kms_account_decrypt_statement,
      local.kms_admin_role_statement,
      {
        Sid       = "AllowDynamoDBUse"
        Effect    = "Allow"
        Principal = { Service = "dynamodb.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncryptFrom", "kms:ReEncryptTo",
          "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey", "kms:CreateGrant",
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowBookPodRoleUse"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.book_pod.arn }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource  = "*"
      },
      {
        Sid       = "AllowBookFunctionRoleUse"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.book_function.arn }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_key" "ecr" {
  description                        = "ECR encryption key"
  deletion_window_in_days            = 7
  enable_key_rotation                = true
  bypass_policy_lockout_safety_check = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.kms_account_admin_statement,
      local.kms_account_decrypt_statement,
      local.kms_admin_role_statement,
      {
        Sid       = "AllowECRUse"
        Effect    = "Allow"
        Principal = { Service = "ecr.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncryptFrom", "kms:ReEncryptTo",
          "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey", "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_kms_key" "eks" {
  description                        = "EKS secrets encryption key"
  deletion_window_in_days            = 7
  enable_key_rotation                = true
  bypass_policy_lockout_safety_check = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.kms_account_admin_statement,
      local.kms_account_decrypt_statement,
      local.kms_admin_role_statement,
      {
        Sid       = "AllowEKSUse"
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext", "kms:DescribeKey", "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_kms_key" "bucket" {
  description                        = "S3 bucket encryption key"
  deletion_window_in_days            = 7
  enable_key_rotation                = true
  bypass_policy_lockout_safety_check = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.kms_account_admin_statement,
      local.kms_account_decrypt_statement,
      local.kms_admin_role_statement,
      {
        Sid       = "AllowS3Use"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncryptFrom", "kms:ReEncryptTo",
          "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey", "kms:CreateGrant",
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowCloudFrontUse"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_key" "function" {
  description                        = "Lambda environment encryption key"
  deletion_window_in_days            = 7
  enable_key_rotation                = true
  bypass_policy_lockout_safety_check = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.kms_account_admin_statement,
      local.kms_account_decrypt_statement,
      local.kms_admin_role_statement,
      {
        Sid       = "AllowLambdaUse"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext", "kms:DescribeKey", "kms:CreateGrant",
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowBookFunctionRoleUse"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.book_function.arn }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
      },
      {
        Sid       = "AllowLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.region}:${local.account_id}:*"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "db" {
  name          = "alias/wsc2026-db-kms"
  target_key_id = aws_kms_key.db.key_id
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/wsc2026-ecr-kms"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_kms_alias" "eks" {
  name          = "alias/wsc2026-eks-kms"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_kms_alias" "bucket" {
  name          = "alias/wsc2026-bucket-kms"
  target_key_id = aws_kms_key.bucket.key_id
}

resource "aws_kms_alias" "function" {
  name          = "alias/wsc2026-function-kms"
  target_key_id = aws_kms_key.function.key_id
}
