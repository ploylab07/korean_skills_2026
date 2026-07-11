resource "aws_kms_key" "keys" {
  for_each = toset(local.kms_aliases)

  description             = each.value
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, { Name = each.value })
}

resource "aws_kms_alias" "keys" {
  for_each = aws_kms_key.keys

  name          = "alias/${each.key}"
  target_key_id = each.value.key_id
}

resource "aws_iam_role" "kms_admin" {
  name = "wsc2026-kms-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = [
          aws_iam_role.bastion.arn,
          "arn:${local.partition}:iam::${local.account_id}:root",
        ]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "kms_admin" {
  name = "wsc2026-kms-admin-policy"
  role = aws_iam_role.kms_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion",
      ]
      Resource = "*"
    }]
  })
}

locals {
  kms_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KeyAdministration"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.kms_admin.arn
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      {
        Sid    = "KeyUsageServices"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.eks_cluster.arn,
            aws_iam_role.book_pod.arn,
            aws_iam_role.book_function.arn,
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
      {
        Sid    = "KeyUsageAWSServices"
        Effect = "Allow"
        Principal = {
          Service = [
            "dynamodb.amazonaws.com",
            "ecr.amazonaws.com",
            "eks.amazonaws.com",
            "s3.amazonaws.com",
            "lambda.amazonaws.com",
            "logs.amazonaws.com",
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = local.account_id
          }
        }
      },
    ]
  })
}

resource "null_resource" "kms_policies" {
  for_each = aws_kms_key.keys

  triggers = {
    key_id   = each.value.id
    policy   = local.kms_policy_json
    role_arn = aws_iam_role.kms_admin.arn
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      source "${path.module}/../../build/load-env.sh"
      load_repo_env "${path.module}/../../build"
      POLICY='${replace(local.kms_policy_json, "'", "'\\''")}'
      aws kms put-key-policy --key-id ${each.value.id} --policy-name default --policy "$POLICY"
    EOT
  }

  depends_on = [
    aws_iam_role_policy.kms_admin,
  ]
}
