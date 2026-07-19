resource "aws_s3_bucket" "web" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
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
  key          = "web/main/index.html"
  source       = "${path.module}/index.html"
  etag         = filemd5("${path.module}/index.html")
  content_type = "text/html"
  server_side_encryption = "aws:kms"
  kms_key_id   = aws_kms_key.s3.arn
}

resource "aws_s3_object" "main_jpeg" {
  bucket       = aws_s3_bucket.web.id
  key          = "web/main/main.jpeg"
  source       = "${path.module}/main.jpeg"
  etag         = filemd5("${path.module}/main.jpeg")
  content_type = "image/jpeg"
  server_side_encryption = "aws:kms"
  kms_key_id   = aws_kms_key.s3.arn
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "wskorea26-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}
