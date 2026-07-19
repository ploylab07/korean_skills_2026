resource "aws_cloudfront_function" "rewrite" {
  name    = "wskorea26-book-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "rewrite POST /book"
  publish = true
  code    = <<-EOF
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var method = request.method;
  if (method === 'POST' && (uri === '/book' || uri.indexOf('/book?') === 0 || uri === '/book/')) {
    request.uri = '/v1/book';
  }
  return request;
}
EOF
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "wskorea26-concert-cf"
  default_root_object = "index.html"
  price_class         = "PriceClass_All"
  http_version        = "http2"
  is_ipv6_enabled     = true

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "wskorea26-s3-origin"
    origin_path              = "/web/main"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id

    custom_header {
      name  = "wskorea26-s3-access"
      value = "true"
    }
  }

  origin {
    domain_name = aws_lb.book.dns_name
    origin_id   = "wskorea26-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = "wskorea26-cf"
    }
  }

  default_cache_behavior {
    target_origin_id       = "wskorea26-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.cache_policy_optimized
    origin_request_policy_id = local.origin_req_cors_s3
  }

  ordered_cache_behavior {
    path_pattern             = "/book*"
    target_origin_id         = "wskorea26-alb-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = local.cache_policy_disabled
    origin_request_policy_id = local.origin_req_all_viewer

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }
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

  tags = { Name = "wskorea26-concert-cf" }
}
