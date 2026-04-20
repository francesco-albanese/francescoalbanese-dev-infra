# ACM statements for the infra deploy role.
data "aws_iam_policy_document" "infra_deploy_acm" {
  statement {
    sid    = "ACMReadOnly"
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate",
      "acm:ListTagsForCertificate",
      "acm:GetCertificate",
      "acm:ListCertificates",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ACMRequestWithTag"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:AddTagsToCertificate",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/franco:terraform_stack"
      values   = ["francescoalbanese-dev-infra"]
    }
  }

  statement {
    sid       = "ACMMutateTagged"
    effect    = "Allow"
    actions   = ["acm:DeleteCertificate"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/franco:terraform_stack"
      values   = ["francescoalbanese-dev-infra"]
    }
  }
}
