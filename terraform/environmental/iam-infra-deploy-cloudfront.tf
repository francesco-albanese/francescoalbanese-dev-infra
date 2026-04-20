# CloudFront statements for the infra deploy role.
data "aws_iam_policy_document" "infra_deploy_cloudfront" {
  statement {
    sid    = "CloudFrontReadOnly"
    effect = "Allow"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:ListTagsForResource",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:GetFunction",
      "cloudfront:DescribeFunction",
      "cloudfront:GetCachePolicy",
      "cloudfront:GetResponseHeadersPolicy",
      "cloudfront:GetCloudFrontOriginAccessIdentity",
      "cloudfront:ListDistributions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudFrontMutate"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:CreateCachePolicy",
      "cloudfront:UpdateCachePolicy",
      "cloudfront:DeleteCachePolicy",
      "cloudfront:CreateResponseHeadersPolicy",
      "cloudfront:UpdateResponseHeadersPolicy",
      "cloudfront:DeleteResponseHeadersPolicy",
      "cloudfront:CreateInvalidation",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/franco:terraform_stack"
      values   = ["francescoalbanese-dev-infra"]
    }
  }

  statement {
    sid    = "CloudFrontFunctions"
    effect = "Allow"
    actions = [
      "cloudfront:CreateFunction",
      "cloudfront:UpdateFunction",
      "cloudfront:DeleteFunction",
      "cloudfront:PublishFunction",
    ]
    resources = ["arn:aws:cloudfront::${var.account_id}:function/*"]
  }
}
