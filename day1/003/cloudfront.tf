resource "aws_cloudfront_function" "booking_rewrite" {
  name    = "wsc2026-booking-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOF
    function handler(event) {
      var request = event.request;
      if (request.uri === '/booking' || request.uri.startsWith('/booking/')) {
        request.uri = request.uri.replace(/^\/booking/, '/v1/book');
      }
      return request;
    }
  EOF
}

resource "aws_wafv2_web_acl" "cdn" {
  provider = aws.us_east_1
  name     = "wsc2026-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "wsc2026-waf-sqli"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

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
      metric_name                = "wsc2026-waf-xss"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 200
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "wsc2026-waf-rate"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "wsc2026-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "wsc2026-waf"
  }
}

resource "aws_cloudfront_distribution" "cdn" {
  provider = aws.us_east_1
  enabled             = true
  default_root_object = "static/index.html"

  tags = {
    Name = "wsc2026-cdn"
  }

  origin {
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = "S3-static"
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  origin {
    domain_name = aws_lb.app.dns_name
    origin_id   = "ALB-booking"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
    }
  }

  origin {
    domain_name = replace(replace(aws_lambda_function_url.book_get.function_url, "https://", ""), "/", "")
    origin_id   = "Lambda-book-get"

    custom_origin_config {
      http_port              = 443
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-static"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = local.cache_policy_optimized
  }

  ordered_cache_behavior {
    path_pattern           = "/booking*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-booking"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = local.cache_policy_disabled

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.booking_rewrite.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/v1/book*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "Lambda-book-get"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = local.cache_policy_disabled
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  web_acl_id = aws_wafv2_web_acl.cdn.arn

  depends_on = [
    aws_s3_object.index,
    aws_s3_object.main_jpeg,
    aws_lambda_function_url.book_get,
    aws_lb.app,
  ]
}
