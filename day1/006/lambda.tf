data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/build/lambda.zip"
  source {
    content  = file("${path.module}/lambda/handler.py")
    filename = "handler.py"
  }
}

resource "aws_lambda_function" "reservation" {
  function_name = "gj2026-book-reservation"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.14"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.books.name
      AWS_REGION_OVERRIDE = local.region
    }
  }

  tags = merge(local.common_tags, { Name = "gj2026-book-reservation" })
}

resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reservation.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
}
