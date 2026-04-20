provider "aws" {
  region = var.region

  default_tags {
    tags = {
      "franco:terraform_stack" = "francescoalbanese-dev-infra-ecr"
      "franco:managed_by"      = "terraform"
      "franco:environment"     = var.account_name
    }
  }
}
