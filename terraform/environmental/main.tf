locals {
  project_prefix = "francescoalbanese-dev"
}

# Route53 hosted zone for francescoalbanese.dev (in shared-services, centralised DNS)
resource "aws_route53_zone" "main" {
  provider = aws.shared_services
  name     = var.domain_name
  comment  = "Hosted zone for ${var.domain_name} - personal domain"
}
