# Route53 hosted zone for francescoalbanese.dev
resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "Hosted zone for ${var.domain_name} - personal domain"
}
