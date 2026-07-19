data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/.build/lambda.zip"
}

resource "aws_lambda_function" "book" {
  function_name = "wskorea26-book-lambda"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.14"
  filename      = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout       = 30
  memory_size   = 256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.data.name
      INDEX_NAME = "concert_name-created_at-index"
    }
  }

  tags = { Name = "wskorea26-book-lambda" }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}
