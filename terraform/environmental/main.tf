locals {
  project_prefix = "francescoalbanese-dev"
}

# Route53 hosted zone for francescoalbanese.dev (in shared-services, centralised DNS)
# Zone already exists from mTLS project — look up, don't create
data "aws_route53_zone" "main" {
  provider = aws.shared_services
  name     = var.domain_name
}
