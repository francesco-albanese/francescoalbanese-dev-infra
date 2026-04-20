# IAM statements for the infra deploy role — manages the deploy roles
# themselves, OIDC provider, lambda exec roles, and the managed boundary policy.
data "aws_iam_policy_document" "infra_deploy_iam" {
  statement {
    sid    = "IAMRolesAndOIDC"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-github-actions-deploy",
      "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-infra-github-actions-deploy",
      "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }

  statement {
    sid     = "IAMCreateRoleWithBoundary"
    effect  = "Allow"
    actions = ["iam:CreateRole"]
    resources = concat(
      [
        "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-github-actions-deploy",
        "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-infra-github-actions-deploy",
      ],
      local.lambda_role_arns,
    )
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.infra_deploy_boundary.arn]
    }
  }

  statement {
    sid    = "IAMManageLambdaExecRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
    ]
    resources = local.lambda_role_arns
  }

  statement {
    sid       = "IAMPassRoleToLambda"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.lambda_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "IAMManagedPolicies"
    effect = "Allow"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
    ]
    resources = ["arn:aws:iam::${var.account_id}:policy/${local.project_prefix}-infra-deploy-boundary"]
  }
}
