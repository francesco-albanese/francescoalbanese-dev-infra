# Permissions boundary — caps privileges for any role created by infra deploy.
# Covers both infra deploy roles (site sync + CF invalidation) and lambda
# runtime roles (analytics bucket access + SNS publish + CloudWatch logs).
data "aws_iam_policy_document" "infra_deploy_boundary" {
  statement {
    sid    = "AllowS3ManagedBuckets"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = concat(
      local.managed_bucket_arns,
      [for b in local.managed_bucket_arns : "${b}/*"],
    )
  }

  statement {
    sid       = "AllowCloudFrontInvalidation"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/franco:terraform_stack"
      values   = ["francescoalbanese-dev-infra"]
    }
  }

  statement {
    sid       = "AllowSNSPublishAnalyticsAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [local.analytics_alerts_topic_arn]
  }

  statement {
    sid    = "AllowCloudWatchLogsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = local.lambda_log_group_arns_wildcard
  }
}

resource "aws_iam_policy" "infra_deploy_boundary" {
  name        = "${local.project_prefix}-infra-deploy-boundary"
  description = "Permissions boundary for roles created by the infra deploy pipeline"
  policy      = data.aws_iam_policy_document.infra_deploy_boundary.json

  tags = {
    Name = "${local.project_prefix}-infra-deploy-boundary"
  }
}
