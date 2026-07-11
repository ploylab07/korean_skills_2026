resource "aws_s3_bucket" "codepipeline" {
  bucket        = "${local.name_prefix}-codepipeline-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_codebuild_source_credential" "github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
}

resource "aws_codebuild_project" "red" {
  name            = "${local.name_prefix}-app-red-build"
  service_role    = aws_iam_role.codebuild.arn
  build_timeout   = 10
  source_version  = "app-red"

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.red.repository_url
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "GITHUB_TOKEN"
      value = aws_secretsmanager_secret.github_token.arn
      type  = "SECRETS_MANAGER"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build_red.name
      status     = "ENABLED"
    }
  }

  source {
    type            = "GITHUB"
    location        = local.github_repo_url
    buildspec       = "buildspec.yaml"
    git_clone_depth = 1
  }

  tags = local.common_tags
}

resource "aws_codebuild_project" "green" {
  name            = "${local.name_prefix}-app-green-build"
  service_role    = aws_iam_role.codebuild.arn
  build_timeout   = 10
  source_version  = "app-green"

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.green.repository_url
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "GITHUB_TOKEN"
      value = aws_secretsmanager_secret.github_token.arn
      type  = "SECRETS_MANAGER"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build_green.name
      status     = "ENABLED"
    }
  }

  source {
    type            = "GITHUB"
    location        = local.github_repo_url
    buildspec       = "buildspec.yaml"
    git_clone_depth = 1
  }

  tags = local.common_tags
}

resource "aws_codepipeline" "red" {
  name     = "${local.name_prefix}-app-red-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner                = var.github_owner
        Repo                 = var.github_repo
        Branch               = "app-red"
        OAuthToken           = var.github_oauth_token
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        ProjectName = aws_codebuild_project.red.name
      }
    }
  }

  tags = local.common_tags
}

resource "aws_codepipeline" "green" {
  name     = "${local.name_prefix}-app-green-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner                = var.github_owner
        Repo                 = var.github_repo
        Branch               = "app-green"
        OAuthToken           = var.github_oauth_token
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        ProjectName = aws_codebuild_project.green.name
      }
    }
  }

  tags = local.common_tags
}
