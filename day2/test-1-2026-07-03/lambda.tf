resource "aws_security_group" "lambda" {
  name        = "${local.prefix}-lambda-sg"
  description = "Lambda function security group"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-lambda-sg" })
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_book.py"
  output_path = "${path.module}/lambda/get_book.zip"
}

resource "aws_lambda_function" "get_book" {
  function_name    = "${local.prefix}-get-table-function"
  role             = aws_iam_role.lambda.arn
  handler          = "get_book.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function_url" "get_book" {
  function_name      = aws_lambda_function.get_book.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

resource "aws_lambda_permission" "function_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.get_book.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
