resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name_prefix}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_object" "marking_sh" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "marking.sh"
  source = "${path.module}/marking.sh"
  etag   = filemd5("${path.module}/marking.sh")
}

resource "aws_s3_object" "day1_sql" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "day1_table_v1.sql"
  source = "${path.module}/day1_table_v1.sql"
  etag   = filemd5("${path.module}/day1_table_v1.sql")
}

resource "aws_s3_object" "red_binary" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "red_1.0.0"
  source = "${path.module}/red_1.0.0"
  etag   = filemd5("${path.module}/red_1.0.0")

  lifecycle {
    ignore_changes = [etag]
  }
}

resource "aws_s3_object" "green_binary" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "green_1.0.0"
  source = "${path.module}/green_1.0.0"
  etag   = filemd5("${path.module}/green_1.0.0")

  lifecycle {
    ignore_changes = [etag]
  }
}

resource "aws_s3_object" "red_binary_v1" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "red_1.0.1"
  source = "${path.module}/red_1.0.1"
  etag   = filemd5("${path.module}/red_1.0.1")

  lifecycle {
    ignore_changes = [etag]
  }
}

resource "aws_s3_object" "green_binary_v1" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "green_1.0.1"
  source = "${path.module}/green_1.0.1"
  etag   = filemd5("${path.module}/green_1.0.1")

  lifecycle {
    ignore_changes = [etag]
  }
}
