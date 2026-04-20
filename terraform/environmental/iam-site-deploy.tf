# IAM role for GitHub Actions deployment (website repo)
resource "aws_iam_role" "github_actions_deploy" {
  name = "${local.project_prefix}-github-actions-deploy"

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
              "repo:francesco-albanese/francescoalbanese.dev:ref:refs/heads/main",
              "repo:francesco-albanese/francescoalbanese.dev:pull_request",
              "repo:francesco-albanese/francescoalbanese.dev:environment:sandbox",
            ]
          }
        }
      },
    ]
  })

  tags = {
    Name = "${local.project_prefix}-github-actions-deploy"
  }
}

# Least-privilege policy: S3 sync + CloudFront invalidation
data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid    = "S3SiteSync"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]
  }

  statement {
    sid       = "CloudFrontInvalidation"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name   = "s3-sync-and-cf-invalidation"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}
