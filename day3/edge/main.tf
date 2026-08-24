provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
      Component = "edge"
    }
  }
}

data "aws_s3_bucket" "images" {
  bucket = var.image_bucket_name
}

resource "aws_cloudfront_origin_access_control" "images" {
  name                              = "${var.project_name}-images-oac"
  description                       = "Private S3 image origin access"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Dynamic APIs must not be cached. Query strings, headers and cookies are still
# forwarded to the ALB so requestid, uuid and application payloads are preserved.
resource "aws_cloudfront_cache_policy" "api_disabled" {
  name        = "${var.project_name}-api-cache-disabled"
  comment     = "Disable caching for user, product and stress APIs"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${var.project_name}-api-origin-request"
  comment = "Forward all viewer data except Host to the ALB"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allExcept"

    headers {
      items = ["Host"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_cache_policy" "images" {
  name        = "${var.project_name}-images-cache"
  comment     = "Cache immutable or infrequently changed product images"
  default_ttl = 300
  max_ttl     = 86400
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

# The task exposes /images/<object path>, while the application stores objects
# as /<object path>. This function removes only the public /images prefix.
resource "aws_cloudfront_function" "rewrite_images" {
  name    = "${var.project_name}-rewrite-images"
  runtime = "cloudfront-js-1.0"
  comment = "Rewrite /images/key to /key for the private S3 origin"
  publish = true

  code = <<-JS
    function handler(event) {
      var request = event.request;
      if (request.uri.indexOf('/images/') === 0) {
        request.uri = request.uri.substring(7);
      }
      return request;
    }
  JS
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} single public endpoint"
  price_class         = "PriceClass_200"
  wait_for_deployment = true

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "application-alb"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  origin {
    domain_name              = data.aws_s3_bucket.images.bucket_regional_domain_name
    origin_id                = "private-image-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.images.id
  }

  default_cache_behavior {
    target_origin_id       = "application-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id          = aws_cloudfront_cache_policy.api_disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = "private-image-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id = aws_cloudfront_cache_policy.images.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_images.arn
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
}

data "aws_iam_policy_document" "images_cloudfront" {
  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${data.aws_s3_bucket.images.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "images_cloudfront" {
  bucket = data.aws_s3_bucket.images.id
  policy = data.aws_iam_policy_document.images_cloudfront.json
}
