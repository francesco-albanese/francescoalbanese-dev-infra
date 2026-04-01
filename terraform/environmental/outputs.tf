output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "nameservers" {
  description = "Nameservers to configure in Porkbun"
  value       = aws_route53_zone.main.name_servers
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN (us-east-1, for CloudFront)"
  value       = aws_acm_certificate.main.arn
}
