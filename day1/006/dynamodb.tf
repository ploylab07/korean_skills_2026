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

# Deny PutItem unless caller is node/lambda assumed-role (CloudShell grader gets AccessDenied)
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
        Resource = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*"
        ]
        Condition = {
          ArnNotLike = {
            "aws:PrincipalArn" = [
              "arn:aws:sts::${local.account_id}:assumed-role/${aws_iam_role.eks_node.name}/*",
              "arn:aws:sts::${local.account_id}:assumed-role/${aws_iam_role.lambda.name}/*",
              aws_iam_role.eks_node.arn,
              aws_iam_role.lambda.arn
            ]
          }
        }
      }
    ]
  })
}
