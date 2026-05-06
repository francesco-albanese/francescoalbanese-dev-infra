# Cross-cutting statements for the infra deploy role:
# STS assume into shared-services, SSM parameter read.
data "aws_iam_policy_document" "infra_deploy_sts_ssm" {
  statement {
    sid       = "AssumeSharedServicesRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${var.shared_services_account_id}:role/${var.shared_services_role_name}"]
  }

  statement {
    sid       = "SsmReadMaxMindLicense"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${var.account_id}:parameter/${local.project_prefix}/maxmind-license-key"]
  }
}
