resource "aws_dynamodb_table" "book" {
  name             = "wsc2026-book-table"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "client_id"
  stream_enabled   = false
  table_class      = "STANDARD"

  deletion_protection_enabled = true

  attribute {
    name = "client_id"
    type = "S"
  }

  attribute {
    name = "booking_id"
    type = "S"
  }

  global_secondary_index {
    name            = "booking_id-index"
    hash_key        = "booking_id"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.db.arn
  }

  point_in_time_recovery {
    enabled                 = true
    recovery_period_in_days = 35
  }

  tags = {
    Name = "wsc2026-book-table"
  }
}

resource "aws_dynamodb_resource_policy" "book" {
  resource_arn = aws_dynamodb_table.book.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPodPutItem"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.book_pod.arn }
        Action    = "dynamodb:PutItem"
        Resource  = aws_dynamodb_table.book.arn
      },
      {
        Sid       = "AllowFunctionQuery"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.book_function.arn }
        Action    = "dynamodb:Query"
        Resource  = [
          aws_dynamodb_table.book.arn,
          "${aws_dynamodb_table.book.arn}/index/*",
        ]
      },
    ]
  })
}

resource "aws_iam_policy" "book_pod" {
  name = "wsc2026-book-pod-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "dynamodb:PutItem"
      Resource = aws_dynamodb_table.book.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "book_pod" {
  role       = aws_iam_role.book_pod.name
  policy_arn = aws_iam_policy.book_pod.arn
}

resource "aws_iam_policy" "book_function" {
  name = "wsc2026-book-function-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/wsc2026-book-get-function:*"
      },
      {
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = [
          aws_dynamodb_table.book.arn,
          "${aws_dynamodb_table.book.arn}/index/*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "book_function" {
  role       = aws_iam_role.book_function.name
  policy_arn = aws_iam_policy.book_function.arn
}
