terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws]
    }
    archive = {
      source = "hashicorp/archive"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  bucket_name = "gj2026-cdn-bucket-${var.participant_id}"
}

resource "aws_s3_bucket" "cdn" {
  bucket = local.bucket_name

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "cdn" {
  bucket = aws_s3_bucket.cdn.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "dog" {
  bucket       = aws_s3_bucket.cdn.id
  key          = "images/dog.png"
  source       = "${path.module}/../../CDN/dog.png"
  etag         = filemd5("${path.module}/../../CDN/dog.png")
  content_type = "image/png"
}

resource "null_resource" "rotate_package" {
  triggers = {
    source = filemd5("${path.module}/lambda/rotate.py")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      PKG="${abspath(path.module)}/.build/rotate_pkg"
      rm -rf "$PKG"
      mkdir -p "$PKG"
      cp "${path.module}/lambda/rotate.py" "$PKG/"
      docker run --rm --platform linux/amd64 --entrypoint pip \
        -v "$PKG:/var/task" \
        -w /var/task \
        public.ecr.aws/lambda/python:3.14 \
        install --quiet Pillow -t /var/task --only-binary=:all:
      rm -rf "$PKG"/*.dist-info "$PKG"/__pycache__ "$PKG"/bin
    EOT
  }
}

data "archive_file" "rotate" {
  depends_on  = [null_resource.rotate_package]
  type        = "zip"
  output_path = "${path.module}/.build/rotate.zip"
  source_dir  = "${path.module}/.build/rotate_pkg"
}

data "archive_file" "request" {
  type        = "zip"
  output_path = "${path.module}/.build/request.zip"
  source {
    content  = file("${path.module}/lambda/request.py")
    filename = "request.py"
  }
}

data "archive_file" "response" {
  type        = "zip"
  output_path = "${path.module}/.build/response.zip"
  source {
    content  = file("${path.module}/lambda/response.py")
    filename = "response.py"
  }
}

resource "aws_iam_role" "lambda" {
  name = "gj2026-cdn-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"] }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "gj2026-cdn-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.cdn.arn}/*"
      }
    ]
  })
}

resource "aws_lambda_function" "rotate" {
  function_name = "gj2026-cdn-rotate"
  role          = aws_iam_role.lambda.arn
  handler       = "rotate.handler"
  runtime       = "python3.14"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.rotate.output_path
  source_code_hash = data.archive_file.rotate.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME  = aws_s3_bucket.cdn.bucket
      IMAGE_PREFIX = "images/"
    }
  }

}

resource "aws_lambda_function_url" "rotate" {
  function_name      = aws_lambda_function.rotate.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

resource "aws_lambda_function" "request" {
  function_name = "gj2026-cdn-request"
  role          = aws_iam_role.lambda.arn
  handler       = "request.handler"
  runtime       = "python3.14"
  timeout       = 5
  memory_size   = 128
  publish       = true

  filename         = data.archive_file.request.output_path
  source_code_hash = data.archive_file.request.output_base64sha256
}

resource "aws_lambda_function" "response" {
  function_name = "gj2026-cdn-response"
  role          = aws_iam_role.lambda.arn
  handler       = "response.handler"
  runtime       = "python3.14"
  timeout       = 5
  memory_size   = 128
  publish       = true

  filename         = data.archive_file.response.output_path
  source_code_hash = data.archive_file.response.output_base64sha256
}

locals {
  rotate_host = replace(replace(aws_lambda_function_url.rotate.function_url, "https://", ""), "/", "")
}

resource "aws_cloudfront_cache_policy" "images" {
  name        = "gj2026-cdn-images-cache"
  comment     = "Cache by image and rotate query strings"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "whitelist"
      query_strings {
        items = ["image", "rotate"]
      }
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "images" {
  name    = "gj2026-cdn-images-origin"
  comment = "Forward image and rotate query strings"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "whitelist"
    query_strings {
      items = ["image", "rotate"]
    }
  }
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "gj2026-cdn"
  price_class     = "PriceClass_100"

  origin {
    domain_name = local.rotate_host
    origin_id   = "lambda-rotate"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "lambda-rotate"
    viewer_protocol_policy = "redirect-to-https"
    compress               = false

    cache_policy_id          = aws_cloudfront_cache_policy.images.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.images.id
  }

  ordered_cache_behavior {
    path_pattern           = "/images"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "lambda-rotate"
    viewer_protocol_policy = "redirect-to-https"
    compress               = false

    cache_policy_id          = aws_cloudfront_cache_policy.images.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.images.id

    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = aws_lambda_function.request.qualified_arn
      include_body = false
    }

    lambda_function_association {
      event_type   = "viewer-response"
      lambda_arn   = aws_lambda_function.response.qualified_arn
      include_body = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "gj2026-cdn"
  }
}
