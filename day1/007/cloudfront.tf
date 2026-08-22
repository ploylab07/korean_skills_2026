resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "unicorn-oac"
  description                       = "OAC for unicorn-web bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "unicorn-alb-vpc-origin"
    arn                    = aws_lb.book.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  tags = merge(local.common_tags, { Name = "unicorn-alb-vpc-origin" })
}

resource "aws_wafv2_web_acl" "unicorn" {
  provider = aws.us_east_1
  name     = "unicorn-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "unicornCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "unicornKnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "unicorn-rate-limit"
    priority = 3

    action {
      block {
        custom_response {
          response_code            = 403
          custom_response_body_key = "rate_limited"
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = 50
        evaluation_window_sec = 60
        aggregate_key_type    = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "unicornRateLimit"
      sampled_requests_enabled   = true
    }
  }

  custom_response_body {
    key          = "rate_limited"
    content      = "Request blocked by Unicorn WAF"
    content_type = "TEXT_PLAIN"
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "unicornWaf"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, { Name = "unicorn-waf" })
}

resource "aws_cloudwatch_log_group" "waf" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-unicorn"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.platform_primary.arn

  depends_on = [aws_kms_key_policy.platform_primary]
}

data "aws_iam_policy_document" "waf_log_resource_policy" {
  provider = aws.us_east_1
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.waf.arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:us-east-1:${local.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  provider        = aws.us_east_1
  policy_name     = "unicorn-waf-logs-policy"
  policy_document = data.aws_iam_policy_document.waf_log_resource_policy.json
}

resource "aws_wafv2_web_acl_logging_configuration" "unicorn" {
  provider                = aws.us_east_1
  resource_arn            = aws_wafv2_web_acl.unicorn.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}

resource "aws_cloudfront_distribution" "unicorn" {
  enabled             = true
  comment             = "unicorn-svc-cf"
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.unicorn.arn
  price_class         = "PriceClass_200"
  http_version        = "http2"
  is_ipv6_enabled     = true

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    domain_name = aws_lb.book.dns_name
    origin_id   = "app-origin"

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }

    custom_header {
      name  = local.origin_verify_header
      value = local.origin_verify_value
    }
  }

  # Default: static assets served from S3 — cached.
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  }

  # /v1/book -> ALB (POST goes to Book App, GET goes to Lambda). No caching.
  # VPC Origin requires AllViewerExceptHostHeader — forwarding viewer Host breaks the origin.
  ordered_cache_behavior {
    path_pattern             = "/v1/book"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "app-origin"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
  }

  # /health -> ALB (Book App liveness). No caching.
  ordered_cache_behavior {
    path_pattern             = "/health"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "app-origin"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(local.common_tags, { Name = "unicorn-svc-cf" })

  depends_on = [aws_s3_object.index, aws_s3_object.main_jpeg]
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.web.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.unicorn.arn
          }
        }
      }
    ]
  })
}
