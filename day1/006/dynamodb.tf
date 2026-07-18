resource "aws_dynamodb_table" "books" {
  name         = "books"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "booking_id"

  attribute {
    name = "booking_id"
    type = "S"
  }

  attribute {
    name = "client_id"
    type = "S"
  }

  global_secondary_index {
    name            = "client_id-index"
    hash_key        = "client_id"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.db.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, { Name = "books" })
}

# Deny PutItem from account root/user used for grading; allow app role
resource "aws_dynamodb_resource_policy" "books" {
  resource_arn = aws_dynamodb_table.books.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyPutFromGraders"
        Effect    = "Deny"
        Principal = "*"
        Action    = "dynamodb:PutItem"
        Resource  = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = [
              aws_iam_role.book_app.arn,
              aws_iam_role.lambda.arn
            ]
          }
        }
      },
      {
        Sid    = "AllowAppAccess"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.book_app.arn,
            aws_iam_role.lambda.arn
          ]
        }
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*"
        ]
      }
    ]
  })
}
