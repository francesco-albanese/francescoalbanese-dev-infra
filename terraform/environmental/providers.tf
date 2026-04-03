provider "aws" {
  region = var.region

  # Auth handled externally:
  # - Local dev: AWS profiles with assume_role in ~/.aws/config
  # - GitHub OIDC: configure-aws-credentials sets env vars

  default_tags {
    tags = {
      "franco:terraform_stack" = "francescoalbanese-dev-infra"
      "franco:managed_by"      = "terraform"
      "franco:environment"     = var.account_name
    }
  }
}

# ACM certificates for CloudFront must be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      "franco:terraform_stack" = "francescoalbanese-dev-infra"
      "franco:managed_by"      = "terraform"
      "franco:environment"     = var.account_name
    }
  }
}

# Cross-account provider for Route53 operations (zone in shared-services)
provider "aws" {
  alias  = "shared_services"
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.shared_services_account_id}:role/${var.shared_services_role_name}"
  }

  default_tags {
    tags = {
      "franco:terraform_stack" = "francescoalbanese-dev-infra"
      "franco:managed_by"      = "terraform"
      "franco:environment"     = var.account_name
    }
  }
}
