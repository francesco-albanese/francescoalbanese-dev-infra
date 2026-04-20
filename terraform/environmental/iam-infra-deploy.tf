# IAM role for GitHub Actions deployment (infra repo)
resource "aws_iam_role" "github_actions_infra_deploy" {
  name = "${local.project_prefix}-infra-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:francesco-albanese/francescoalbanese-dev-infra:environment:sandbox",
            ]
          }
        }
      },
    ]
  })

  tags = {
    Name = "${local.project_prefix}-infra-github-actions-deploy"
  }
}

# Scoped IAM policy for infra deploy role.
# Statements live in per-service files (iam-infra-deploy-*.tf) and are
# composed here via source_policy_documents into a single inline policy.
data "aws_iam_policy_document" "github_actions_infra_deploy" {
  source_policy_documents = [
    data.aws_iam_policy_document.infra_deploy_s3.json,
    data.aws_iam_policy_document.infra_deploy_cloudfront.json,
    data.aws_iam_policy_document.infra_deploy_acm.json,
    data.aws_iam_policy_document.infra_deploy_iam.json,
    data.aws_iam_policy_document.infra_deploy_ecr.json,
    data.aws_iam_policy_document.infra_deploy_lambda_logs.json,
    data.aws_iam_policy_document.infra_deploy_sns_ssm.json,
  ]
}

resource "aws_iam_role_policy" "github_actions_infra_deploy" {
  name   = "infra-deploy"
  role   = aws_iam_role.github_actions_infra_deploy.id
  policy = data.aws_iam_policy_document.github_actions_infra_deploy.json
}
