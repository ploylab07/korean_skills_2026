output "bucket_name" {
  value = aws_s3_bucket.score.bucket
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.student_score.arn
}

output "score_function_name" {
  value = aws_lambda_function.student_score.function_name
}
