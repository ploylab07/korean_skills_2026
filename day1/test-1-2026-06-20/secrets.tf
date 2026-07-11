resource "aws_kms_key" "ecr" {
  description             = "ECR KMS encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-ecr-kms" })
}

resource "aws_ecr_repository" "red" {
  name                 = "red"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "green" {
  name                 = "green"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "build_red" {
  name              = "/gj2025/build/red"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "build_green" {
  name              = "/gj2025/build/green"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "app_red" {
  name              = "/gj2025/app/red"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "app_green" {
  name              = "/gj2025/app/green"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_secretsmanager_secret" "db_catalog" {
  name                    = "${local.name_prefix}-eks-cluster-catalog-secret"
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_catalog" {
  secret_id = aws_secretsmanager_secret.db_catalog.id
  secret_string = jsonencode({
    DB_USER   = "admin"
    DB_PASSWD = var.db_password
    DB_URL    = "${aws_db_proxy.main.endpoint}:3306"
  })

  depends_on = [aws_db_proxy.main]
}

resource "aws_secretsmanager_secret" "github_token" {
  name                    = "${local.name_prefix}-github-token"
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "github_token" {
  secret_id     = aws_secretsmanager_secret.github_token.id
  secret_string = var.github_token
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}-db-credentials"
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "admin"
    password = var.db_password
  })
}
