# Cross-cutting statements for the infra deploy role:
# STS assume into shared-services, SNS alert-topic management, SSM parameter read.
data "aws_iam_policy_document" "infra_deploy_sns_ssm" {
  statement {
    sid       = "AssumeSharedServicesRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${var.shared_services_account_id}:role/${var.shared_services_role_name}"]
  }

  statement {
    sid    = "SnsManageAnalyticsAlerts"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:ListTagsForResource",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]
    resources = [local.analytics_alerts_topic_arn]
  }

  statement {
    sid       = "SsmReadMaxMindLicense"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${var.account_id}:parameter/${local.project_prefix}/maxmind-license-key"]
  }
}
