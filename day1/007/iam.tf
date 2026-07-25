# --- EKS cluster role ---
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
  name               = "unicorn-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- EKS node role (managed node groups, Bottlerocket) ---
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "unicorn-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Fluent Bit (DaemonSet, no dedicated Pod Identity) ships via the node role.
resource "aws_iam_role_policy" "node_fluentbit_logs" {
  name = "unicorn-node-fluentbit-logs"
  role = aws_iam_role.eks_node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.book_app.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*"
      },
      {
        # CloudWatch Grafana panel (ALB latency) — read-only metrics access
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Pod Identity role for the Book App (namespace: unicorn, ServiceAccount: book) ---
data "aws_iam_policy_document" "book_app_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_eks_cluster.main.arn]
    }
  }
}

resource "aws_iam_role" "book_app" {
  name               = "unicorn-book-app-role"
  assume_role_policy = data.aws_iam_policy_document.book_app_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "book_app" {
  name = "unicorn-book-app-policy"
  role = aws_iam_role.book_app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.concert.arn,
          "${aws_dynamodb_table.concert.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.app.arn]
      }
    ]
  })
}

# --- Lambda execution role (unicorn-get-booking-func) ---
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_get_booking" {
  name               = "unicorn-get-booking-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "lambda_get_booking" {
  name = "unicorn-get-booking-policy"
  role = aws_iam_role.lambda_get_booking.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.concert.arn,
          "${aws_dynamodb_table.concert.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.app.arn, aws_kms_replica_key.platform.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/unicorn/lambda/get-booking",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/unicorn/lambda/get-booking:*"
        ]
      }
    ]
  })
}

# --- Audit role (assume-only via ExternalId, read-only least privilege) ---
data "aws_iam_policy_document" "audit_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["unicorn-audit-2026${local.bib}"]
    }
  }
}

resource "aws_iam_role" "audit" {
  name                 = "unicorn-audit-role"
  assume_role_policy   = data.aws_iam_policy_document.audit_assume.json
  max_session_duration = 3600
  tags                 = local.common_tags
}

resource "aws_iam_role_policy" "audit" {
  name = "unicorn-audit-policy"
  role = aws_iam_role.audit.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDbReadOnly"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.concert.arn,
          "${aws_dynamodb_table.concert.arn}/index/*"
        ]
      },
      {
        Sid      = "Ec2DescribeVpcs"
        Effect   = "Allow"
        Action   = ["ec2:DescribeVpcs"]
        Resource = "*"
      },
      {
        Sid      = "EksDescribeCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = [aws_eks_cluster.main.arn]
      }
    ]
  })
}
