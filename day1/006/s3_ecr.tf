resource "aws_s3_bucket" "web" {
  bucket = local.bucket_name
  tags   = merge(local.common_tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "web" {
  bucket = aws_s3_bucket.web.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.web.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
  source_hash  = filemd5("${path.module}/index.html")

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.s3.arn
}

resource "aws_s3_object" "main_jpeg" {
  bucket       = aws_s3_bucket.web.id
  key          = "main.jpeg"
  source       = "${path.module}/main.jpeg"
  content_type = "image/jpeg"
  source_hash  = filemd5("${path.module}/main.jpeg")

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.s3.arn
}

resource "aws_ecr_repository" "book" {
  name                 = "book"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { Name = "book" })
}

resource "aws_ecr_repository" "hostname_bootstrap" {
  name                 = "hostname-bootstrap"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, { Name = "hostname-bootstrap" })
}
