resource "aws_s3_bucket" "static" {
  bucket = local.bucket_name
  tags   = merge(local.common_tags, { Name = local.bucket_name })
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
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.keys["wsc2026-bucket-kms"].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_object" "index" {
  bucket     = aws_s3_bucket.static.id
  key        = "static/index.html"
  source     = "${path.module}/index.html"
  kms_key_id = aws_kms_key.keys["wsc2026-bucket-kms"].arn
}

resource "aws_s3_object" "main_image" {
  bucket     = aws_s3_bucket.static.id
  key        = "static/main.jpeg"
  source     = "${path.module}/main.jpeg"
  kms_key_id = aws_kms_key.keys["wsc2026-bucket-kms"].arn
}

resource "aws_s3_object" "static_prefix" {
  bucket = aws_s3_bucket.static.id
  key    = "static/"
}

resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "wsc2026-static-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFront"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.static.arn}/*"
      Condition = {
        StringLike = {
          "AWS:SourceArn" = "arn:${local.partition}:cloudfront::${local.account_id}:distribution/*"
        }
      }
    }]
  })
}
