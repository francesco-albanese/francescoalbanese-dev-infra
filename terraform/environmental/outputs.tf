output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "nameservers" {
  description = "Nameservers to configure in Porkbun"
  value       = aws_route53_zone.main.name_servers
}
