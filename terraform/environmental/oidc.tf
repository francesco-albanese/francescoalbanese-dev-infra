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
              "repo:francesco-albanese/francescoalbanese.dev:pull_request",
              "repo:francesco-albanese/francescoalbanese.dev:environment:sandbox"
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
              "repo:francesco-albanese/francescoalbanese-dev-infra:environment:sandbox"
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

# Permissions boundary — caps privileges for any role created by infra deploy.
# Covers both infra deploy roles (site sync + CF invalidation) and lambda
# runtime roles (analytics bucket access + SNS publish + CloudWatch logs).
resource "aws_iam_policy" "infra_deploy_boundary" {
  name        = "${local.project_prefix}-infra-deploy-boundary"
  description = "Permissions boundary for roles created by the infra deploy pipeline"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ManagedBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = concat(
          local.managed_bucket_arns,
          [for b in local.managed_bucket_arns : "${b}/*"]
        )
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
        Sid      = "AllowSNSPublishAnalyticsAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = local.analytics_alerts_topic_arn
      },
      {
        Sid    = "AllowCloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.lambda_log_group_arns_wildcard
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
        # S3 bucket-level management on managed buckets (site + analytics).
        # Object-level CRUD happens via the site-deploy role (see above) and
        # via lambda runtime roles (see boundary), not here.
        Sid    = "S3ManagedBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketAcl",
          "s3:PutBucketAcl",
          "s3:GetBucketOwnershipControls",
          "s3:PutBucketOwnershipControls",
          "s3:DeleteBucketOwnershipControls",
          "s3:GetBucketCORS",
          "s3:PutBucketCORS",
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
          "s3:PutLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:PutBucketVersioning"
        ]
        Resource = local.managed_bucket_arns
      },
      {
        # Required by data.aws_canonical_user_id (needed for CloudFront v1
        # log-delivery ACL on the analytics bucket). ListAllMyBuckets is
        # inherently global — cannot be ARN-scoped.
        Sid      = "S3ListAllMyBuckets"
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
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
        Sid    = "CloudFrontFunctions"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateFunction",
          "cloudfront:UpdateFunction",
          "cloudfront:DeleteFunction",
          "cloudfront:PublishFunction"
        ]
        Resource = "arn:aws:cloudfront::${var.account_id}:function/*"
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
          "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-github-actions-deploy",
          "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-infra-github-actions-deploy",
          "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
        ]
      },
      {
        Sid    = "IAMCreateRoleWithBoundary"
        Effect = "Allow"
        Action = "iam:CreateRole"
        Resource = concat(
          [
            "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-github-actions-deploy",
            "arn:aws:iam::${var.account_id}:role/${local.project_prefix}-infra-github-actions-deploy"
          ],
          local.lambda_role_arns
        )
        Condition = {
          StringEquals = {
            "iam:PermissionsBoundary" = aws_iam_policy.infra_deploy_boundary.arn
          }
        }
      },
      {
        Sid    = "IAMManageLambdaExecRoles"
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
          "iam:PutRolePermissionsBoundary",
          "iam:DeleteRolePermissionsBoundary"
        ]
        Resource = local.lambda_role_arns
      },
      {
        Sid      = "IAMPassRoleToLambda"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.lambda_role_arns
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "lambda.amazonaws.com"
          }
        }
      },
      {
        Sid    = "IAMManagedPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:ListPolicyVersions",
          "iam:TagPolicy"
        ]
        Resource = "arn:aws:iam::${var.account_id}:policy/${local.project_prefix}-infra-deploy-boundary"
      },
      {
        # GetAuthorizationToken is inherently registry-wide — AWS requires "*".
        # The returned token is scoped to this account's registry.
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        # Push + read (used by docker build-push + terraform data source refresh)
        Sid    = "EcrPushAndRead"
        Effect = "Allow"
        Action = [
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
          "ecr:ListTagsForResource"
        ]
        Resource = local.ecr_lambda_repo_arns
      },
      {
        # Repo lifecycle management (terraform/ecr stack)
        Sid    = "EcrManageRepos"
        Effect = "Allow"
        Action = [
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
          "ecr:DeleteRepositoryPolicy"
        ]
        Resource = local.ecr_lambda_repo_arns
      },
      {
        Sid    = "LambdaManageAnalyticsFunctions"
        Effect = "Allow"
        Action = [
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
          "lambda:DeleteFunctionConcurrency"
        ]
        Resource = local.lambda_function_arns
      },
      {
        # DescribeLogGroups is required on refresh; it must target a log-group
        # prefix (AWS does not allow it against a specific log-group ARN).
        Sid      = "LogsDescribeLambdaGroups"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${local.project_prefix}-*"
      },
      {
        Sid    = "LogsManageLambdaGroups"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:ListTagsForResource",
          "logs:ListTagsLogGroup"
        ]
        Resource = concat(
          local.lambda_log_group_arns,
          local.lambda_log_group_arns_wildcard
        )
      },
      {
        Sid    = "SnsManageAnalyticsAlerts"
        Effect = "Allow"
        Action = [
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
          "sns:ListSubscriptionsByTopic"
        ]
        Resource = local.analytics_alerts_topic_arn
      },
      {
        Sid      = "SsmReadMaxMindLicense"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}:${var.account_id}:parameter/${local.project_prefix}/maxmind-license-key"
      },
    ]
  })
}
