resource "null_resource" "lambda_runtime_314" {
  triggers = {
    function_version = aws_lambda_function.get_book.version
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-configuration --function-name ${aws_lambda_function.get_book.function_name} --runtime python3.14 --region ${var.region} || true"
  }

  depends_on = [aws_lambda_function.get_book]
}
