# Email forwarding via Porkbun (Route53 is authoritative)
resource "aws_route53_record" "email_mx" {
  provider = aws.shared_services
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = var.domain_name
  type     = "MX"
  ttl      = 300

  records = [
    "10 fwd1.porkbun.com",
    "20 fwd2.porkbun.com",
  ]
}

resource "aws_route53_record" "email_spf" {
  provider = aws.shared_services
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = var.domain_name
  type     = "TXT"
  ttl      = 300

  records = [
    "v=spf1 include:_spf.porkbun.com ~all",
  ]
}
