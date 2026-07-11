resource "aws_dynamodb_table" "book" {
  name             = "wsc2026-book-table"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "client_id"
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
    kms_key_arn = aws_kms_key.keys["wsc2026-db-kms"].arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, { Name = "wsc2026-book-table" })
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
        Sid       = "AllowLambdaQuery"
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
