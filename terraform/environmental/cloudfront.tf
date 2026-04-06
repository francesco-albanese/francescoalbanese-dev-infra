# State moves for renamed resources (safe to remove after first apply)
moved {
  from = aws_cloudfront_function.redirect_bare_to_www
  to   = aws_cloudfront_function.redirect_www_to_bare
}

moved {
  from = aws_route53_record.site_bare_a
  to   = aws_route53_record.site_www_a
}

moved {
  from = aws_route53_record.site_bare_aaaa
  to   = aws_route53_record.site_www_aaaa
}

# CloudFront Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.project_prefix}-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Function: redirect www to bare domain
resource "aws_cloudfront_function" "redirect_www_to_bare" {
  name    = "redirect-bare-to-www"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/dist/redirect-www-to-bare.js")
}

# Response headers policy with security headers
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "${local.project_prefix}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    # CSP moved to <meta> tag in HTML — Astro inlines scripts/styles that need
    # per-build SHA-256 hashes, which can't be hardcoded here. See app repo
    # docs/adr/001-csp-hash-strategy.md for rationale.

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

# Cache policy for hashed assets (long TTL)
resource "aws_cloudfront_cache_policy" "hashed_assets" {
  name        = "${local.project_prefix}-hashed-assets"
  default_ttl = 31536000
  max_ttl     = 31536000
  min_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
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

# Cache policy for index.html (short TTL)
resource "aws_cloudfront_cache_policy" "short_ttl" {
  name        = "${local.project_prefix}-short-ttl"
  default_ttl = 300
  max_ttl     = 300
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
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

# CloudFront distribution
resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name, "www.${var.domain_name}"]
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # Default cache behavior (short TTL — safe for index.html, robots.txt, favicon, etc.)
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "s3-site"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.short_ttl.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect_www_to_bare.arn
    }
  }

  # Ordered cache behavior for Astro hashed assets (long TTL — 1 year)
  ordered_cache_behavior {
    path_pattern               = "/_astro/*"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "s3-site"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.hashed_assets.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect_www_to_bare.arn
    }
  }

  # SPA error handling: serve index.html for 403/404
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 60
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${local.project_prefix}-site"
  }
}

# S3 bucket policy allowing CloudFront OAC access
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}

# Route53 records pointing to CloudFront (shared-services)
resource "aws_route53_record" "site_a" {
  provider = aws.shared_services
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = var.domain_name
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "site_aaaa" {
  provider = aws.shared_services
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = var.domain_name
  type     = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "site_www_a" {
  provider = aws.shared_services
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "www.${var.domain_name}"
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "site_www_aaaa" {
  provider = aws.shared_services
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "www.${var.domain_name}"
  type     = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
