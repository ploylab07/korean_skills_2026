data "archive_file" "book_get" {
  type        = "zip"
  source_file = "${path.module}/lambda/book_get.py"
  output_path = "${path.module}/lambda/book_get.zip"
}

resource "aws_lambda_function" "book_get" {
  function_name = "wsc2026-book-get-function"
  role          = aws_iam_role.book_function.arn
  handler       = "book_get.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  kms_key_arn   = aws_kms_key.keys["wsc2026-function-kms"].arn

  filename         = data.archive_file.book_get.output_path
  source_code_hash = data.archive_file.book_get.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.book.name
    }
  }

  depends_on = [aws_iam_role_policy_attachment.book_function_basic]
}

resource "aws_lambda_function_url" "book_get" {
  function_name      = aws_lambda_function.book_get.function_name
  authorization_type = "NONE"
}
