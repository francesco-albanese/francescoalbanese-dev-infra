# ─── Analytics: Locals ────────────────────────────────────────────────────────
# analytics_bucket_name / analytics_bucket_arn live in main.tf alongside site

locals {
  analytics_tags = {
    "franco:terraform_stack" = "francescoalbanese-dev-infra-analytics"
    "franco:environment"     = var.account_name
    "franco:managed_by"      = "terraform"
  }
}

# ─── Analytics: ECR data lookups ─────────────────────────────────────────────
# Repos are owned by the terraform/ecr stack. Apply that stack — and push at
# least one image to each repo — before applying this stack.

data "aws_ecr_repository" "log_enricher" {
  name = "${local.project_prefix}-log-enricher"
}

data "aws_ecr_repository" "dashboard_generator" {
  name = "${local.project_prefix}-dashboard-generator"
}

# ─── Analytics: S3 Bucket ─────────────────────────────────────────────────────

resource "aws_s3_bucket" "analytics" {
  bucket = local.analytics_bucket_name

  tags = merge(local.analytics_tags, {
    Name = "${local.project_prefix}-analytics"
  })
}

resource "aws_s3_bucket_ownership_controls" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  # BucketOwnerPreferred (not Enforced) because CloudFront v1 access logging
  # writes via ACLs; v2 supported no-ACLs but is cross-region-locked.
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

data "aws_canonical_user_id" "current" {}

resource "aws_s3_bucket_acl" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  access_control_policy {
    owner {
      id = data.aws_canonical_user_id.current.id
    }

    grant {
      grantee {
        id   = data.aws_canonical_user_id.current.id
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }

    # CloudFront log-delivery canonical user (static, AWS-owned).
    grant {
      grantee {
        id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
  }

  depends_on = [aws_s3_bucket_ownership_controls.analytics]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  rule {
    id     = "cf-logs"
    status = "Enabled"
    filter {
      prefix = "cf-logs/"
    }
    expiration {
      days = 7
    }
  }

  rule {
    id     = "enriched"
    status = "Enabled"
    filter {
      prefix = "enriched/"
    }
    expiration {
      days = 14
    }
  }

  rule {
    id     = "dashboard"
    status = "Enabled"
    filter {
      prefix = "dashboard/"
    }
    expiration {
      days = 7
    }
  }

  rule {
    id     = "alerts"
    status = "Enabled"
    filter {
      prefix = "alerts/"
    }
    expiration {
      days = 30
    }
  }
}

# CloudFront v1 access logging writes directly to the analytics bucket via the
# `logging_config` block on aws_cloudfront_distribution.site — see cloudfront.tf.
# The ACL above grants the CF log-delivery canonical user write access.

# ─── Analytics: IAM Roles ─────────────────────────────────────────────────────

resource "aws_iam_role" "log_enricher" {
  name                 = "${local.project_prefix}-log-enricher"
  permissions_boundary = aws_iam_policy.infra_deploy_boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.analytics_tags, {
    Name = "${local.project_prefix}-log-enricher"
  })
}

resource "aws_iam_role_policy" "log_enricher" {
  name = "log-enricher-permissions"
  role = aws_iam_role.log_enricher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCFLogs"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.analytics.arn}/cf-logs/*"
      },
      {
        Sid      = "WriteEnriched"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.analytics.arn}/enriched/*"
      },
      {
        Sid      = "ListEnriched"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.analytics.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["enriched/*"]
          }
        }
      },
      {
        Sid      = "AlertDeduplication"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.analytics.arn}/alerts/*"
      },
      {
        Sid      = "PublishAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.analytics_alerts.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.log_enricher.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role" "dashboard_generator" {
  name                 = "${local.project_prefix}-dashboard-generator"
  permissions_boundary = aws_iam_policy.infra_deploy_boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.analytics_tags, {
    Name = "${local.project_prefix}-dashboard-generator"
  })
}

resource "aws_iam_role_policy" "dashboard_generator" {
  name = "dashboard-generator-permissions"
  role = aws_iam_role.dashboard_generator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadEnriched"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.analytics.arn}/enriched/*"
      },
      {
        Sid      = "ListEnriched"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.analytics.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["enriched/*"]
          }
        }
      },
      {
        Sid      = "WriteDashboard"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.analytics.arn}/dashboard/*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.dashboard_generator.arn}:*"
      }
    ]
  })
}

# ─── Analytics: CloudWatch Log Groups ─────────────────────────────────────────

resource "aws_cloudwatch_log_group" "log_enricher" {
  name              = "/aws/lambda/${local.project_prefix}-log-enricher"
  retention_in_days = 30

  tags = merge(local.analytics_tags, {
    Name = "${local.project_prefix}-log-enricher"
  })
}

resource "aws_cloudwatch_log_group" "dashboard_generator" {
  name              = "/aws/lambda/${local.project_prefix}-dashboard-generator"
  retention_in_days = 30

  tags = merge(local.analytics_tags, {
    Name = "${local.project_prefix}-dashboard-generator"
  })
}

# ─── Analytics: Lambda Functions ──────────────────────────────────────────────

resource "aws_lambda_function" "log_enricher" {
  function_name = "${local.project_prefix}-log-enricher"
  role          = aws_iam_role.log_enricher.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.log_enricher.repository_url}:${var.image_tag_log_enricher}"
  architectures = ["arm64"]
  timeout       = 60
  memory_size   = 256

  environment {
    variables = {
      ANALYTICS_BUCKET = aws_s3_bucket.analytics.id
      SNS_TOPIC_ARN    = aws_sns_topic.analytics_alerts.arn
      GEOIP_DB_PATH    = "/opt/GeoLite2-City.mmdb"
    }
  }

  depends_on = [aws_cloudwatch_log_group.log_enricher]

  tags = merge(local.analytics_tags, {
    Name = "${local.project_prefix}-log-enricher"
  })
}

resource "aws_lambda_function" "dashboard_generator" {
  function_name = "${local.project_prefix}-dashboard-generator"
  role          = aws_iam_role.dashboard_generator.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.dashboard_generator.repository_url}:${var.image_tag_dashboard_generator}"
  architectures = ["arm64"]
  timeout       = 120
  memory_size   = 512

  environment {
    variables = {
      ANALYTICS_BUCKET = aws_s3_bucket.analytics.id
    }
  }

  depends_on = [aws_cloudwatch_log_group.dashboard_generator]

  tags = merge(local.analytics_tags, {
    Name = "${local.project_prefix}-dashboard-generator"
  })
}

# ─── Analytics: S3 Event → log-enricher trigger ───────────────────────────────

resource "aws_lambda_permission" "s3_invoke_log_enricher" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.log_enricher.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.analytics.arn
  source_account = var.account_id
}

resource "aws_s3_bucket_notification" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.log_enricher.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "cf-logs/"
  }

  depends_on = [aws_lambda_permission.s3_invoke_log_enricher]
}

# ─── Analytics: SNS ──────────────────────────────────────────────────────────

resource "aws_sns_topic" "analytics_alerts" {
  name = "${local.project_prefix}-analytics-alerts"

  tags = merge(local.analytics_tags, {
    Name = "${local.project_prefix}-analytics-alerts"
  })
}

resource "aws_sns_topic_subscription" "analytics_email" {
  topic_arn = aws_sns_topic.analytics_alerts.arn
  protocol  = "email"
  endpoint  = var.analytics_alert_email
}

# ─── Analytics: Outputs ──────────────────────────────────────────────────────

output "analytics_bucket_name" {
  description = "Analytics S3 bucket name"
  value       = aws_s3_bucket.analytics.id
}

output "dashboard_generator_function_name" {
  description = "Dashboard Lambda function name (invoke via `make dashboard`)"
  value       = aws_lambda_function.dashboard_generator.function_name
}
