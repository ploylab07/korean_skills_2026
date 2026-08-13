############################################
# Module 2 — CDN A/B (us-east-1 / virginia)
############################################

resource "aws_s3_bucket" "landing" {
  provider      = aws.virginia
  bucket        = local.landing_bucket_name
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "landing" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.landing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "version_a" {
  provider     = aws.virginia
  bucket       = aws_s3_bucket.landing.id
  key          = "version-a/index.html"
  source       = "${path.module}/Module2-CDN-Function/index_a.html"
  etag         = filemd5("${path.module}/Module2-CDN-Function/index_a.html")
  content_type = "text/html"
}

resource "aws_s3_object" "version_b" {
  provider     = aws.virginia
  bucket       = aws_s3_bucket.landing.id
  key          = "version-b/index.html"
  source       = "${path.module}/Module2-CDN-Function/index_b.html"
  etag         = filemd5("${path.module}/Module2-CDN-Function/index_b.html")
  content_type = "text/html"
}

############################################
# CloudFront OAC + bucket policy
############################################

resource "aws_cloudfront_origin_access_control" "landing" {
  provider                          = aws.virginia
  name                              = "skillsphone-cdn-ab-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "landing_bucket" {
  provider = aws.virginia

  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.landing.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.landing.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "landing" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.landing.id
  policy   = data.aws_iam_policy_document.landing_bucket.json
}

############################################
# CloudFront KeyValueStore
############################################

resource "aws_cloudfront_key_value_store" "ab_config" {
  provider = aws.virginia
  name     = "skillsphone-cdn-ab-config"
}

resource "aws_cloudfrontkeyvaluestore_key" "weight" {
  provider             = aws.virginia
  key_value_store_arn  = aws_cloudfront_key_value_store.ab_config.arn
  key                  = "weight"
  value                = "0.3"
}

resource "aws_cloudfrontkeyvaluestore_key" "version_a" {
  provider             = aws.virginia
  key_value_store_arn  = aws_cloudfront_key_value_store.ab_config.arn
  key                  = "version_a"
  value                = "/version-a/index.html"
}

resource "aws_cloudfrontkeyvaluestore_key" "version_b" {
  provider             = aws.virginia
  key_value_store_arn  = aws_cloudfront_key_value_store.ab_config.arn
  key                  = "version_b"
  value                = "/version-b/index.html"
}

############################################
# CloudFront Functions
############################################

resource "aws_cloudfront_function" "viewer_request" {
  provider = aws.virginia
  name     = "skillsphone-cdn-ab-req-fn"
  runtime  = "cloudfront-js-2.0"
  publish  = true
  code     = file("${path.module}/Module2-CDN-Function/viewer-request.js")

  key_value_store_associations = [aws_cloudfront_key_value_store.ab_config.arn]
}

resource "aws_cloudfront_function" "viewer_response" {
  provider = aws.virginia
  name     = "skillsphone-cdn-ab-res-fn"
  runtime  = "cloudfront-js-2.0"
  publish  = true
  code     = file("${path.module}/Module2-CDN-Function/viewer-response.js")
}

############################################
# Cache policy
############################################

resource "aws_cloudfront_cache_policy" "ab_cache" {
  provider    = aws.virginia
  name        = "skillsphone-cdn-ab-cache-policy"
  min_ttl     = 0
  default_ttl = 300
  max_ttl     = 3600

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "whitelist"
      cookies {
        items = ["x-sp-ab"]
      }
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

############################################
# Custom response headers policy
############################################

resource "aws_cloudfront_response_headers_policy" "ab_security" {
  provider = aws.virginia
  name     = "skillsphone-cdn-ab-security-headers"

  security_headers_config {
    strict_transport_security {
      override                   = true
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      override     = true
      frame_option = "DENY"
    }
    referrer_policy {
      override        = true
      referrer_policy = "strict-origin-when-cross-origin"
    }
  }
}

############################################
# CloudFront distribution
############################################

resource "aws_cloudfront_distribution" "landing" {
  provider            = aws.virginia
  enabled             = true
  comment             = "skillsphone-cdn-ab-distribution"
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.landing.bucket_regional_domain_name
    origin_id                = "skillsphone-landing-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.landing.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = "skillsphone-landing-s3"
    viewer_protocol_policy  = "redirect-to-https"
    cache_policy_id          = aws_cloudfront_cache_policy.ab_cache.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.ab_security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }

    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.viewer_response.arn
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

  tags = local.common_tags
}
