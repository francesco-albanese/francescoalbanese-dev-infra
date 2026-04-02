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

output "site_bucket_id" {
  description = "S3 bucket name for static site"
  value       = aws_s3_bucket.site.id
}

output "site_bucket_arn" {
  description = "S3 bucket ARN for static site"
  value       = aws_s3_bucket.site.arn
}

output "site_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name (for CloudFront OAC)"
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.site.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "github_actions_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC deployment (website repo)"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "github_actions_infra_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC deployment (infra repo)"
  value       = aws_iam_role.github_actions_infra_deploy.arn
}
