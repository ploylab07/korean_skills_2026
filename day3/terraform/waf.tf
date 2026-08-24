# -------------------- WAF and request validation --------------------
resource "aws_wafv2_web_acl" "main" {
  name  = "${local.name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # A request to a defined API path without requestid is considered invalid.
  # Unknown paths do not match this rule and are returned as 404 by the ALB.
  rule {
    name     = "BlockMissingRequestId"
    priority = 1

    action {
      block {
        custom_response {
          response_code = 403
        }
      }
    }

    statement {
      and_statement {
        statement {
          or_statement {
            statement {
              byte_match_statement {
                search_string         = "/v1/user"
                positional_constraint = "EXACTLY"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }

            statement {
              byte_match_statement {
                search_string         = "/v1/product"
                positional_constraint = "EXACTLY"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }

            statement {
              byte_match_statement {
                search_string         = "/v1/stress"
                positional_constraint = "EXACTLY"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }

        statement {
          not_statement {
            statement {
              or_statement {
                statement {
                  byte_match_statement {
                    search_string         = "requestid"
                    positional_constraint = "CONTAINS"

                    field_to_match {
                      query_string {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }

                statement {
                  byte_match_statement {
                    search_string         = "requestid"
                    positional_constraint = "CONTAINS"

                    field_to_match {
                      body {
                        oversize_handling = "CONTINUE"
                      }
                    }

                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-missing-requestid"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "BlockMissingUuid"
    priority = 2

    action {
      block {
        custom_response {
          response_code = 403
        }
      }
    }

    statement {
      and_statement {
        statement {
          or_statement {
            statement {
              byte_match_statement {
                search_string         = "/v1/user"
                positional_constraint = "EXACTLY"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }

            statement {
              byte_match_statement {
                search_string         = "/v1/product"
                positional_constraint = "EXACTLY"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }

            statement {
              byte_match_statement {
                search_string         = "/v1/stress"
                positional_constraint = "EXACTLY"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }

        statement {
          not_statement {
            statement {
              or_statement {
                statement {
                  byte_match_statement {
                    search_string         = "uuid"
                    positional_constraint = "CONTAINS"

                    field_to_match {
                      query_string {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }

                statement {
                  byte_match_statement {
                    search_string         = "uuid"
                    positional_constraint = "CONTAINS"

                    field_to_match {
                      body {
                        oversize_handling = "CONTINUE"
                      }
                    }

                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-missing-uuid"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "BlockInvalidUserMethod"
    priority = 3

    action {
      block {
        custom_response {
          response_code = 403
        }
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = "/v1/user"
            positional_constraint = "EXACTLY"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              or_statement {
                statement {
                  byte_match_statement {
                    search_string         = "GET"
                    positional_constraint = "EXACTLY"

                    field_to_match {
                      method {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }

                statement {
                  byte_match_statement {
                    search_string         = "POST"
                    positional_constraint = "EXACTLY"

                    field_to_match {
                      method {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-invalid-user-method"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "BlockInvalidProductMethod"
    priority = 4

    action {
      block {
        custom_response {
          response_code = 403
        }
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = "/v1/product"
            positional_constraint = "EXACTLY"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              or_statement {
                statement {
                  byte_match_statement {
                    search_string         = "GET"
                    positional_constraint = "EXACTLY"

                    field_to_match {
                      method {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }

                statement {
                  byte_match_statement {
                    search_string         = "POST"
                    positional_constraint = "EXACTLY"

                    field_to_match {
                      method {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }

                statement {
                  byte_match_statement {
                    search_string         = "PUT"
                    positional_constraint = "EXACTLY"

                    field_to_match {
                      method {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-invalid-product-method"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "BlockInvalidStressMethod"
    priority = 5

    action {
      block {
        custom_response {
          response_code = 403
        }
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = "/v1/stress"
            positional_constraint = "EXACTLY"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              byte_match_statement {
                search_string         = "POST"
                positional_constraint = "EXACTLY"

                field_to_match {
                  method {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-invalid-stress-method"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedCommonRules"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Multipart image uploads can exceed the ALB WAF body inspection size.
        # Keep these detections visible as metrics without blocking the valid PUT.
        rule_action_override {
          name = "SizeRestrictions_BODY"

          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "CrossSiteScripting_BODY"

          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedKnownBadInputs"
    priority = 20

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
      metric_name                = "${local.name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "PerIpRateLimit"
    priority = 30

    action {
      block {
        custom_response {
          response_code = 403
        }
      }
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "FORWARDED_IP"

        forwarded_ip_config {
          fallback_behavior = "MATCH"
          header_name       = "X-Forwarded-For"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}
