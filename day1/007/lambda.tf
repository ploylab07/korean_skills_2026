data "archive_file" "get_booking" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/build/lambda_function.zip"
}

resource "aws_cloudwatch_log_group" "get_booking" {
  name              = "/unicorn/lambda/get-booking"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform.arn

  depends_on = [aws_kms_key_policy.platform_replica]
}

resource "aws_lambda_function" "get_booking" {
  function_name = "unicorn-get-booking-func"
  role          = aws_iam_role.lambda_get_booking.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 15
  memory_size   = 256
  kms_key_arn   = aws_kms_replica_key.platform.arn

  filename         = data.archive_file.get_booking.output_path
  source_code_hash = data.archive_file.get_booking.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.concert.name
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.get_booking.name
  }

  tags = merge(local.common_tags, { Name = "unicorn-get-booking-func" })

  depends_on = [aws_cloudwatch_log_group.get_booking]
}

resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_booking.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}
