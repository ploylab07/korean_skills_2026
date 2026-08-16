resource "aws_ecr_repository" "book" {
  name                 = "wskorea26-book-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}

resource "null_resource" "book_image" {
  triggers = {
    book_hash = filesha256("${path.module}/book")
    repo_url  = aws_ecr_repository.book.repository_url
  }

  provisioner "local-exec" {
    interpreter = local.local_exec_interpreter
    command     = <<-EOT
      set -e
      ACCOUNT=${local.account_id}
      REGION=${var.region}
      REPO=${aws_ecr_repository.book.repository_url}
      aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
      docker build -t "$REPO:stable" -f "${local.module_posix}/Dockerfile" "${local.module_posix}"
      docker push "$REPO:stable"
    EOT
  }

  lifecycle {
    ignore_changes = [triggers]
  }

  depends_on = [aws_ecr_repository.book]
}

resource "aws_dynamodb_table" "data" {
  name                        = "wskorea26-data-table"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "client_id"
  deletion_protection_enabled = true

  attribute {
    name = "client_id"
    type = "S"
  }

  attribute {
    name = "concert_name"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "concert_name-created_at-index"
    hash_key        = "concert_name"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  tags = { Name = "wskorea26-data-table" }
}
