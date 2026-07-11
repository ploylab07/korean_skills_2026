resource "aws_s3_bucket" "static" {
  bucket        = "${local.prefix}-static-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

resource "aws_s3_object" "static_index" {
  bucket      = aws_s3_bucket.static.id
  key         = "static/index.html"
  source      = "${path.module}/index.html"
  etag        = filemd5("${path.module}/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "static_image" {
  bucket      = aws_s3_bucket.static.id
  key         = "static/main.jpeg"
  source      = "${path.module}/main.jpeg"
  etag        = filemd5("${path.module}/main.jpeg")
  content_type = "image/jpeg"
}

resource "aws_s3_object" "book" {
  bucket = aws_s3_bucket.static.id
  key    = "artifacts/book"
  source = "${path.module}/book"
  etag   = filemd5("${path.module}/book")
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
