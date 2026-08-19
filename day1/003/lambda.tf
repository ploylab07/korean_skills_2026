data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/wsc2026-book-get-function"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.function.arn
}

resource "aws_lambda_function" "book_get" {
  function_name = "wsc2026-book-get-function"
  role          = aws_iam_role.book_function.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  kms_key_arn   = aws_kms_key.function.arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.book.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_lambda_function_url" "book_get" {
  function_name      = aws_lambda_function.book_get.function_name
  authorization_type = "NONE"

  cors {
    allow_methods = ["GET"]
    allow_origins = ["*"]
  }
}

resource "aws_lambda_permission" "book_get_url" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.book_get.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
