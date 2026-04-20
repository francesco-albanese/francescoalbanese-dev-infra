# ECR statements for the infra deploy role.
data "aws_iam_policy_document" "infra_deploy_ecr" {
  # GetAuthorizationToken is inherently registry-wide — AWS requires "*".
  # The returned token is scoped to this account's registry.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push + read (used by docker build-push + terraform data source refresh)
  statement {
    sid    = "EcrPushAndRead"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages",
      "ecr:ListTagsForResource",
    ]
    resources = local.ecr_lambda_repo_arns
  }

  # Repo lifecycle management (terraform/ecr stack)
  statement {
    sid    = "EcrManageRepos"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy",
    ]
    resources = local.ecr_lambda_repo_arns
  }
}
