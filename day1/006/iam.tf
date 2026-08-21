data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "gj2026-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Separate node roles so aws-auth username can match CN:
# system:node:gj2026.{{SessionName}}.{addon|app}.node  (SessionName = instance-id)
resource "aws_iam_role" "eks_addon_node" {
  name               = "gj2026-eks-addon-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role" "eks_app_node" {
  name               = "gj2026-eks-app-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.common_tags
}

locals {
  node_role_names = {
    addon = aws_iam_role.eks_addon_node.name
    app   = aws_iam_role.eks_app_node.name
  }
  node_role_ids = {
    addon = aws_iam_role.eks_addon_node.id
    app   = aws_iam_role.eks_app_node.id
  }
  node_role_arns = {
    addon = aws_iam_role.eks_addon_node.arn
    app   = aws_iam_role.eks_app_node.arn
  }
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  for_each   = local.node_role_names
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  for_each   = local.node_role_names
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  for_each   = local.node_role_names
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  for_each   = local.node_role_names
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Book app uses app-node instance role (IMDS)
resource "aws_iam_role_policy" "node_ddb_cw" {
  for_each = local.node_role_ids
  name     = "gj2026-node-ddb-cw"
  role     = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.db.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      }
    ]
  })
}

# Book app IRSA / Pod Identity role
data "aws_iam_policy_document" "book_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
  statement {
    # temporary IRSA-style until OIDC ready; also allow EC2 for debugging
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "book_app" {
  name               = "gj2026-book-app-role"
  assume_role_policy = data.aws_iam_policy_document.book_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "book_app_ddb" {
  name = "gj2026-book-app-ddb"
  role = aws_iam_role.book_app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.db.arn]
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "gj2026-book-reservation-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ddb" {
  name = "gj2026-lambda-ddb"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]
        Resource = [aws_kms_key.db.arn]
      }
    ]
  })
}
