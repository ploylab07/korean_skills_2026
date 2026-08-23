terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws]
    }
    archive = {
      source = "hashicorp/archive"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

data "archive_file" "student_score" {
  type                    = "zip"
  source_content          = file("${path.module}/../../module1/lambda-function.py")
  source_content_filename = "index.py"
  output_path             = "${path.module}/student-score.zip"
}

data "archive_file" "s3_trigger" {
  type                    = "zip"
  source_content_filename = "index.py"
  output_path             = "${path.module}/s3-trigger.zip"
  source_content          = <<-PYTHON
    import json
    import os
    from urllib.parse import unquote_plus

    import boto3

    sfn = boto3.client("stepfunctions")


    def handler(event, context):
        state_machine_arn = os.environ["STATE_MACHINE_ARN"]
        started = 0
        for record in event.get("Records", []):
            key = unquote_plus(record["s3"]["object"]["key"])
            sfn.start_execution(
                stateMachineArn=state_machine_arn,
                input=json.dumps({"key": key}),
            )
            started += 1
        return {"statusCode": 200, "started": started}
  PYTHON
}

resource "aws_s3_bucket" "score" {
  provider      = aws
  bucket        = "wsc2026-student-score-bucket-${var.participant_id}"
  force_destroy = true
}

resource "aws_s3_object" "folders" {
  provider = aws
  for_each = toset(["input/", "processed/", "error/"])

  bucket       = aws_s3_bucket.score.id
  key          = each.value
  content      = ""
  content_type = "application/x-directory"
}

resource "aws_dynamodb_table" "student_score" {
  provider     = aws
  name         = "wsc2026-student-score"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "studentId"
  range_key    = "examDate"

  attribute {
    name = "studentId"
    type = "S"
  }

  attribute {
    name = "examDate"
    type = "S"
  }
}

data "aws_caller_identity" "current" {
  provider = aws
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "stepfunctions_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_student" {
  provider           = aws
  name               = "wsc2026-lambda-student-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy" "lambda_student" {
  provider = aws
  name     = "student-score-access"
  role     = aws_iam_role.lambda_student.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.score.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.student_score.arn
      },
      {
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = "arn:aws:states:ap-southeast-1:${data.aws_caller_identity.current.account_id}:stateMachine:wsc2026-student-score-workflow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  provider   = aws
  role       = aws_iam_role.lambda_student.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "stepfunction_student" {
  provider           = aws
  name               = "wsc2026-stepfunction-student-role"
  assume_role_policy = data.aws_iam_policy_document.stepfunctions_assume_role.json
}

resource "aws_iam_role_policy" "stepfunction_student" {
  provider = aws
  name     = "student-score-workflow-access"
  role     = aws_iam_role.stepfunction_student.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.score.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.student_score.arn
      }
    ]
  })
}

resource "aws_lambda_function" "student_score" {
  provider         = aws
  function_name    = "wsc2026-student-score-function"
  role             = aws_iam_role.lambda_student.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.student_score.output_path
  source_code_hash = data.archive_file.student_score.output_base64sha256
  timeout          = 30

  depends_on = [aws_iam_role_policy.lambda_student]

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.score.bucket
      DDB_TABLE = aws_dynamodb_table.student_score.name
    }
  }
}

resource "aws_sfn_state_machine" "student_score" {
  provider     = aws
  name         = "wsc2026-student-score-workflow"
  type         = "STANDARD"
  role_arn     = aws_iam_role.stepfunction_student.arn
  depends_on   = [aws_iam_role_policy.stepfunction_student]
  definition = jsonencode({
    Comment = "Student score workflow"
    StartAt = "CheckS3File"
    States = {
      CheckS3File = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:headObject"
        Parameters = {
          Bucket  = aws_s3_bucket.score.bucket
          "Key.$" = "$.key"
        }
        ResultPath = "$.head"
        Next       = "ProcessStudentData"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "FailState"
        }]
      }
      ProcessStudentData = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.student_score.arn
          Payload = {
            "key.$" = "$.key"
          }
        }
        ResultPath = "$.lambdaResult"
        Retry = [{
          ErrorEquals     = ["States.ALL"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }]
        Next = "CheckResult"
      }
      CheckResult = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.lambdaResult.Payload.statusCode"
          NumericEquals = 200
          Next          = "MoveToProcessed"
        }]
        Default = "MoveToError"
      }
      MoveToProcessed = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:copyObject"
        Parameters = {
          Bucket         = aws_s3_bucket.score.bucket
          "CopySource.$" = "States.Format('${aws_s3_bucket.score.bucket}/{}', $.key)"
          "Key.$"        = "States.Format('processed/{}', States.ArrayGetItem(States.StringSplit($.key, '/'), 1))"
        }
        ResultPath = null
        Next       = "DeleteInputProcessed"
      }
      DeleteInputProcessed = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:deleteObject"
        Parameters = {
          Bucket  = aws_s3_bucket.score.bucket
          "Key.$" = "$.key"
        }
        End = true
      }
      MoveToError = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:copyObject"
        Parameters = {
          Bucket         = aws_s3_bucket.score.bucket
          "CopySource.$" = "States.Format('${aws_s3_bucket.score.bucket}/{}', $.key)"
          "Key.$"        = "States.Format('error/{}', States.ArrayGetItem(States.StringSplit($.key, '/'), 1))"
        }
        ResultPath = null
        Next       = "DeleteInputError"
      }
      DeleteInputError = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:deleteObject"
        Parameters = {
          Bucket  = aws_s3_bucket.score.bucket
          "Key.$" = "$.key"
        }
        Next = "FailState"
      }
      FailState = {
        Type  = "Fail"
        Error = "WorkflowError"
        Cause = "Student score workflow failed"
      }
    }
  })
}

resource "aws_lambda_function" "s3_trigger" {
  provider         = aws
  function_name    = "wsc2026-student-score-trigger"
  role             = aws_iam_role.lambda_student.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.s3_trigger.output_path
  source_code_hash = data.archive_file.s3_trigger.output_base64sha256
  timeout          = 30

  depends_on = [aws_iam_role_policy.lambda_student]

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.student_score.arn
    }
  }
}

resource "aws_lambda_permission" "allow_s3_trigger" {
  provider      = aws
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.score.arn
}

resource "aws_s3_bucket_notification" "student_score" {
  provider = aws
  bucket   = aws_s3_bucket.score.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3_trigger]
}

# S3 notification 전파 전에 ObjectCreated 가 나가면 트리거가 누락될 수 있어 짧게 대기 후 업로드.
resource "time_sleep" "wait_s3_notification" {
  create_duration = "20s"

  depends_on = [aws_s3_bucket_notification.student_score]
}

# 워크플로가 input/ → processed/ 로 파일을 옮기므로 aws_s3_object 로 관리하면 plan 이 매번 create 로 더러워짐.
data "aws_region" "current" {
  provider = aws
}

resource "terraform_data" "seed_test_csv" {
  input = filemd5("${path.module}/../../module1/test.csv")

  provisioner "local-exec" {
    # Git Bash (Windows contest PC) — cmd.exe 는 따옴표/경로에서 깨짐
    interpreter = ["bash", "-c"]
    command     = "aws s3 cp \"${path.module}/../../module1/test.csv\" \"s3://${aws_s3_bucket.score.id}/input/test.csv\" --region \"${data.aws_region.current.region}\""
  }

  depends_on = [
    aws_s3_object.folders,
    time_sleep.wait_s3_notification,
  ]
}

# Allows the asynchronous S3 → Lambda → Step Functions workflow to finish before apply returns.
resource "time_sleep" "wait_for_workflow" {
  create_duration = "60s"

  depends_on = [terraform_data.seed_test_csv]
}
