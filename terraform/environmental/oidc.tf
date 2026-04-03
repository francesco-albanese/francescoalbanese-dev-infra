# GitHub OIDC provider
# AWS stopped validating GitHub OIDC thumbprints in 2023 — use static dummy
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
}

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
              "repo:francesco-albanese/francescoalbanese.dev:pull_request"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.project_prefix}-github-actions-deploy"
  }
}

# Least-privilege policy: S3 sync + CloudFront invalidation
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "s3-sync-and-cf-invalidation"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3SiteSync"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ]
      },
      {
        Sid      = "CloudFrontInvalidation"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = aws_cloudfront_distribution.site.arn
      }
    ]
  })
}

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
              "repo:francesco-albanese/francescoalbanese-dev-infra:ref:refs/heads/main",
              "repo:francesco-albanese/francescoalbanese-dev-infra:pull_request"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.project_prefix}-infra-github-actions-deploy"
  }
}

# Permissions boundary — caps privileges for any role created by infra deploy
resource "aws_iam_policy" "infra_deploy_boundary" {
  name        = "${local.project_prefix}-infra-deploy-boundary"
  description = "Permissions boundary for roles created by the infra deploy pipeline"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::francescoalbanese-*",
          "arn:aws:s3:::francescoalbanese-*/*"
        ]
      },
      {
        Sid      = "AllowCloudFrontInvalidation"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/franco:terraform_stack" = "francescoalbanese-dev-infra"
          }
        }
      },
      {
        Sid    = "AllowSTSAssumeRole"
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Resource = [
          "arn:aws:iam::${var.account_id}:role/francescoalbanese-*"
        ]
      }
    ]
  })

  tags = {
    Name = "${local.project_prefix}-infra-deploy-boundary"
  }
}

# Scoped IAM policy for infra deploy role
resource "aws_iam_role_policy" "github_actions_infra_deploy" {
  name = "infra-deploy"
  role = aws_iam_role.github_actions_infra_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeSharedServicesRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::${var.shared_services_account_id}:role/${var.shared_services_role_name}"
      },
      {
        Sid    = "S3"
        Effect = "Allow"
        Action = [
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketWebsite",
          "s3:GetBucketVersioning",
          "s3:GetBucketLogging",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketRequestPayment",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:PutBucketVersioning"
        ]
        Resource = "arn:aws:s3:::francescoalbanese-*"
      },
      {
        Sid    = "CloudFrontReadOnly"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:ListTagsForResource",
          "cloudfront:GetOriginAccessControl",
          "cloudfront:GetFunction",
          "cloudfront:DescribeFunction",
          "cloudfront:GetCachePolicy",
          "cloudfront:GetResponseHeadersPolicy",
          "cloudfront:GetCloudFrontOriginAccessIdentity",
          "cloudfront:ListDistributions"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudFrontMutate"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution",
          "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:CreateFunction",
          "cloudfront:UpdateFunction",
          "cloudfront:DeleteFunction",
          "cloudfront:PublishFunction",
          "cloudfront:CreateCachePolicy",
          "cloudfront:UpdateCachePolicy",
          "cloudfront:DeleteCachePolicy",
          "cloudfront:CreateResponseHeadersPolicy",
          "cloudfront:UpdateResponseHeadersPolicy",
          "cloudfront:DeleteResponseHeadersPolicy",
          "cloudfront:CreateInvalidation"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/franco:terraform_stack" = "francescoalbanese-dev-infra"
          }
        }
      },
      {
        Sid    = "ACMReadOnly"
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListTagsForCertificate",
          "acm:GetCertificate",
          "acm:ListCertificates"
        ]
        Resource = "*"
      },
      {
        Sid    = "ACMRequestWithTag"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:AddTagsToCertificate"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/franco:terraform_stack" = "francescoalbanese-dev-infra"
          }
        }
      },
      {
        Sid    = "ACMMutateTagged"
        Effect = "Allow"
        Action = [
          "acm:DeleteCertificate"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/franco:terraform_stack" = "francescoalbanese-dev-infra"
          }
        }
      },
      {
        Sid    = "IAMRolesAndOIDC"
        Effect = "Allow"
        Action = [
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
          "iam:ListOpenIDConnectProviders"
        ]
        Resource = [
          "arn:aws:iam::${var.account_id}:role/francescoalbanese-*",
          "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
        ]
      },
      {
        Sid      = "IAMCreateRoleWithBoundary"
        Effect   = "Allow"
        Action   = "iam:CreateRole"
        Resource = "arn:aws:iam::${var.account_id}:role/francescoalbanese-*"
        Condition = {
          StringEquals = {
            "iam:PermissionsBoundary" = aws_iam_policy.infra_deploy_boundary.arn
          }
        }
      },
    ]
  })
}
