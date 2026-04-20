# Lambda + CloudWatch Logs statements for the infra deploy role.
data "aws_iam_policy_document" "infra_deploy_lambda_logs" {
  statement {
    sid    = "LambdaManageAnalyticsFunctions"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:ListVersionsByFunction",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:PutFunctionConcurrency",
      "lambda:DeleteFunctionConcurrency",
    ]
    resources = local.lambda_function_arns
  }

  # DescribeLogGroups is a list-style action. When the AWS provider refreshes
  # log-group state without a logGroupNamePrefix filter, AWS evaluates auth
  # against the service-list ARN form (`log-group::log-stream:*`), which a
  # specific log-group-name prefix can't match. Grant both forms: the Lambda
  # prefix (for prefix-scoped calls) and the service-list form (for no-prefix
  # calls). Read-only action; no mutation scope widens.
  statement {
    sid     = "LogsDescribeLambdaGroups"
    effect  = "Allow"
    actions = ["logs:DescribeLogGroups"]
    resources = [
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${local.project_prefix}-*",
      "arn:aws:logs:${var.region}:${var.account_id}:log-group::log-stream:*",
    ]
  }

  statement {
    sid    = "LogsManageLambdaGroups"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
    ]
    resources = concat(
      local.lambda_log_group_arns,
      local.lambda_log_group_arns_wildcard,
    )
  }
}
