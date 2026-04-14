# ─── Analytics: S3 Bucket ─────────────────────────────────────────────────────

locals {
  analytics_bucket_name = "${local.project_prefix}-analytics-${var.account_id}"
}

resource "aws_s3_bucket" "analytics" {
  bucket = local.analytics_bucket_name

  tags = {
    Name = "${local.project_prefix}-analytics"
  }
}

# ACLs required for CloudFront standard log delivery
resource "aws_s3_bucket_ownership_controls" "analytics" {
  bucket = aws_s3_bucket.analytics.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "analytics" {
  depends_on = [aws_s3_bucket_ownership_controls.analytics]
  bucket     = aws_s3_bucket.analytics.id
  acl        = "log-delivery-write"
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
    id     = "delete-after-90-days"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# ─── Analytics: ECR Repositories ─────────────────────────────────────────────

resource "aws_ecr_repository" "log_enricher" {
  name                 = "${local.project_prefix}-log-enricher"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.project_prefix}-log-enricher"
  }
}

resource "aws_ecr_repository" "dashboard_generator" {
  name                 = "${local.project_prefix}-dashboard-generator"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.project_prefix}-dashboard-generator"
  }
}

resource "aws_ecr_lifecycle_policy" "log_enricher" {
  repository = aws_ecr_repository.log_enricher.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "dashboard_generator" {
  repository = aws_ecr_repository.dashboard_generator.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ─── Analytics: IAM Roles ─────────────────────────────────────────────────────

resource "aws_iam_role" "log_enricher" {
  name = "${local.project_prefix}-log-enricher"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${local.project_prefix}-log-enricher"
  }
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
        Sid    = "ReadWriteEnriched"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject"]
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
        Sid    = "AlertDeduplication"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:HeadObject"]
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
  name = "${local.project_prefix}-dashboard-generator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${local.project_prefix}-dashboard-generator"
  }
}

resource "aws_iam_role_policy" "dashboard_generator" {
  name = "dashboard-generator-permissions"
  role = aws_iam_role.dashboard_generator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadEnriched"
        Effect = "Allow"
        Action = ["s3:GetObject"]
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
        Sid    = "WriteDashboard"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
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

  tags = {
    Name = "${local.project_prefix}-log-enricher"
  }
}

resource "aws_cloudwatch_log_group" "dashboard_generator" {
  name              = "/aws/lambda/${local.project_prefix}-dashboard-generator"
  retention_in_days = 30

  tags = {
    Name = "${local.project_prefix}-dashboard-generator"
  }
}

# ─── Analytics: Lambda Functions ──────────────────────────────────────────────

resource "aws_lambda_function" "log_enricher" {
  function_name = "${local.project_prefix}-log-enricher"
  role          = aws_iam_role.log_enricher.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.log_enricher.repository_url}:latest"
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

  tags = {
    Name = "${local.project_prefix}-log-enricher"
  }
}

resource "aws_lambda_function" "dashboard_generator" {
  function_name = "${local.project_prefix}-dashboard-generator"
  role          = aws_iam_role.dashboard_generator.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.dashboard_generator.repository_url}:latest"
  architectures = ["arm64"]
  timeout       = 120
  memory_size   = 512

  environment {
    variables = {
      ANALYTICS_BUCKET = aws_s3_bucket.analytics.id
    }
  }

  depends_on = [aws_cloudwatch_log_group.dashboard_generator]

  tags = {
    Name = "${local.project_prefix}-dashboard-generator"
  }
}

# ─── Analytics: Lambda Function URL (dashboard) ──────────────────────────────

resource "aws_lambda_function_url" "dashboard_generator" {
  function_name      = aws_lambda_function.dashboard_generator.function_name
  authorization_type = "NONE"
}

# ─── Analytics: S3 Event → Lambda trigger ─────────────────────────────────────

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

  tags = {
    Name = "${local.project_prefix}-analytics-alerts"
  }
}

resource "aws_sns_topic_subscription" "analytics_email" {
  topic_arn = aws_sns_topic.analytics_alerts.arn
  protocol  = "email"
  endpoint  = "hello@francescoalbanese.dev"
}

# ─── Analytics: Outputs ──────────────────────────────────────────────────────

output "dashboard_function_url" {
  description = "Bookmark this URL to access the analytics dashboard"
  value       = aws_lambda_function_url.dashboard_generator.function_url
}

output "analytics_bucket_name" {
  description = "Analytics S3 bucket name"
  value       = aws_s3_bucket.analytics.id
}

output "log_enricher_ecr_uri" {
  description = "ECR repository URI for log-enricher Lambda"
  value       = aws_ecr_repository.log_enricher.repository_url
}

output "dashboard_generator_ecr_uri" {
  description = "ECR repository URI for dashboard-generator Lambda"
  value       = aws_ecr_repository.dashboard_generator.repository_url
}
