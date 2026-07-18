resource "aws_s3_bucket" "static" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.bucket.arn
    }
  }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static.id
  key          = "static/index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/index.html")

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.bucket.arn
}

resource "aws_s3_object" "main_jpeg_root" {
  bucket       = aws_s3_bucket.static.id
  key          = "main.jpeg"
  source       = "${path.module}/main.jpeg"
  content_type = "image/jpeg"
  etag         = filemd5("${path.module}/main.jpeg")

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.bucket.arn
}

resource "aws_s3_object" "main_jpeg" {
  bucket       = aws_s3_bucket.static.id
  key          = "static/main.jpeg"
  source       = "${path.module}/main.jpeg"
  content_type = "image/jpeg"
  etag         = filemd5("${path.module}/main.jpeg")

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.bucket.arn
}

data "aws_iam_policy_document" "static_oac" {
  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.static_oac.json

  depends_on = [aws_cloudfront_distribution.cdn]
}

resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "wsc2026-static-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
