locals {
  project_prefix        = "francescoalbanese-dev"
  site_bucket_name      = "${local.project_prefix}-site-${var.account_id}"
  site_bucket_arn       = "arn:aws:s3:::${local.site_bucket_name}"
  analytics_bucket_name = "${local.project_prefix}-analytics-${var.account_id}"
  analytics_bucket_arn  = "arn:aws:s3:::${local.analytics_bucket_name}"
  managed_bucket_arns   = [local.site_bucket_arn, local.analytics_bucket_arn]

  # Lambda analytics stack — predictable ARNs used by IAM policies
  lambda_names = ["log-enricher", "dashboard-generator"]
  lambda_role_arns = [
    for n in local.lambda_names : "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-${n}"
  ]
  lambda_function_arns = [
    for n in local.lambda_names : "arn:aws:lambda:${var.region}:${var.account_id}:function:${local.project_prefix}-${n}"
  ]
  lambda_log_group_arns = [
    for n in local.lambda_names : "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${local.project_prefix}-${n}"
  ]
  lambda_log_group_arns_wildcard = [for a in local.lambda_log_group_arns : "${a}:*"]
  analytics_alerts_topic_arn     = "arn:aws:sns:${var.region}:${var.account_id}:${local.project_prefix}-analytics-alerts"
  ecr_lambda_repo_arns = [
    for n in local.lambda_names : "arn:aws:ecr:${var.region}:${var.account_id}:repository/${local.project_prefix}-${n}"
  ]
}

# Route53 hosted zone for francescoalbanese.dev (in shared-services, centralised DNS)
# Zone already exists from mTLS project — look up, don't create
data "aws_route53_zone" "main" {
  provider = aws.shared_services
  name     = var.domain_name
}
