# S3 statements for the infra deploy role.
# Bucket-level management on managed buckets (site + analytics).
# Object-level CRUD happens via the site-deploy role (iam-site-deploy.tf) and
# via lambda runtime roles (through the boundary), not here.
data "aws_iam_policy_document" "infra_deploy_s3" {
  statement {
    sid    = "S3ManagedBuckets"
    effect = "Allow"
    actions = [
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
      "s3:PutBucketVersioning",
    ]
    resources = local.managed_bucket_arns
  }

  # Required by data.aws_canonical_user_id (needed for CloudFront v1
  # log-delivery ACL on the analytics bucket). ListAllMyBuckets is
  # inherently global — cannot be ARN-scoped.
  statement {
    sid       = "S3ListAllMyBuckets"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }
}
