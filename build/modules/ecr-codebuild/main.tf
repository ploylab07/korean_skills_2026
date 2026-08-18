locals {
  bucket_name = lower(substr(replace("${var.name_prefix}-cb-${var.account_id}", "_", "-"), 0, 63))
  tags_csv    = join(",", var.image_tags)

  # Windows: pathexpand("~") is C:\Users\... ; use PowerShell waiter (no Git bash required).
  is_windows  = substr(pathexpand("~"), 1, 1) == ":"
  wait_script = local.is_windows ? replace(abspath("${path.module}/wait-codebuild.ps1"), "\\", "/") : replace(abspath("${path.module}/wait-codebuild.sh"), "\\", "/")

  buildspec = <<-EOF
    version: 0.2
    phases:
      pre_build:
        commands:
          - echo Logging in to Amazon ECR...
          - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
          - echo Repo $REPO_URI tags $IMAGE_TAGS
      build:
        commands:
          - echo Build started on `date`
          - docker build -f ${var.dockerfile} -t $REPO_URI:build .
          - |
            IFS=',' read -ra TAGS <<< "$IMAGE_TAGS"
            for t in "$${TAGS[@]}"; do
              docker tag $REPO_URI:build "$REPO_URI:$t"
            done
      post_build:
        commands:
          - |
            IFS=',' read -ra TAGS <<< "$IMAGE_TAGS"
            for t in "$${TAGS[@]}"; do
              docker push "$REPO_URI:$t"
              echo Pushed $REPO_URI:$t
            done
    EOF
}

data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.context_dir
  output_path = "${path.module}/.build/${var.name_prefix}-src.zip"
  excludes    = var.excludes
}

resource "aws_s3_bucket" "source" {
  bucket        = local.bucket_name
  force_destroy = true
  tags          = { Name = local.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "source" {
  bucket = aws_s3_bucket.source.id
  key    = "${var.name_prefix}/source.zip"
  source = data.archive_file.source.output_path
  etag   = data.archive_file.source.output_md5
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/codebuild/${var.name_prefix}"
  retention_in_days = 7

  # Previous failed apply can leave this group outside state.
  lifecycle {
    ignore_changes = [retention_in_days]
  }
}

resource "aws_iam_role" "codebuild" {
  name = substr("${var.name_prefix}-codebuild", 0, 64)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.name_prefix}-codebuild"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "Logs"
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ]
          Resource = [
            aws_cloudwatch_log_group.build.arn,
            "${aws_cloudwatch_log_group.build.arn}:*",
          ]
        },
        {
          Sid      = "S3Source"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:GetObjectVersion"]
          Resource = ["${aws_s3_bucket.source.arn}/*"]
        },
        {
          Sid      = "S3List"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = [aws_s3_bucket.source.arn]
        },
        {
          Sid    = "ECRAuth"
          Effect = "Allow"
          Action = ["ecr:GetAuthorizationToken"]
          Resource = ["*"]
        },
        {
          Sid    = "ECRPush"
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
            "ecr:DescribeRepositories",
          ]
          Resource = ["arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.ecr_repository_name}"]
        },
      ],
      var.ecr_kms_key_arn != null ? [
        {
          Sid      = "KmsEcr"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
          Resource = [var.ecr_kms_key_arn]
        }
      ] : []
    )
  })
}

resource "aws_codebuild_project" "image" {
  name          = substr(replace(var.name_prefix, "_", "-"), 0, 255)
  description   = "Build and push ${var.ecr_repository_name} image (no local Docker)"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = var.build_timeout_min

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = var.ecr_repository_name
    }
    environment_variable {
      name  = "IMAGE_TAGS"
      value = local.tags_csv
    }
    environment_variable {
      name  = "REPO_URI"
      value = var.ecr_repository_url
    }
  }

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.source.bucket}/${aws_s3_object.source.key}"
    buildspec = local.buildspec
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
      status     = "ENABLED"
    }
  }

  depends_on = [aws_iam_role_policy.codebuild]
}

# Trigger build and wait (needs aws CLI on the contest machine — not Docker)
resource "null_resource" "run_build" {
  triggers = {
    source_md5 = data.archive_file.source.output_md5
    project    = aws_codebuild_project.image.name
    tags       = local.tags_csv
    repo       = var.ecr_repository_url
  }

  provisioner "local-exec" {
    interpreter = local.is_windows ? ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"] : ["bash"]
    command     = local.wait_script
    environment = {
      TF_CB_PROJECT      = aws_codebuild_project.image.name
      TF_CB_REGION       = var.region
      AWS_DEFAULT_REGION = var.region
    }
  }

  depends_on = [
    aws_codebuild_project.image,
    aws_s3_object.source,
  ]
}
