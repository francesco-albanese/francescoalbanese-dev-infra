locals {
  project_prefix   = "francescoalbanese-dev"
  site_bucket_name = "${local.project_prefix}-site-${var.account_id}"
  site_bucket_arn  = "arn:aws:s3:::${local.site_bucket_name}"
}

# Route53 hosted zone for francescoalbanese.dev (in shared-services, centralised DNS)
# Zone already exists from mTLS project — look up, don't create
data "aws_route53_zone" "main" {
  provider = aws.shared_services
  name     = var.domain_name
}
