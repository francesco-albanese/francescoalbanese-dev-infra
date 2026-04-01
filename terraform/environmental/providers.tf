provider "aws" {
  region = var.region

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
