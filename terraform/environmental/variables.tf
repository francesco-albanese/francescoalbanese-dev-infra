variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "account_id" {
  description = "AWS account ID for target account"
  type        = string
}

variable "account_name" {
  description = "The name of the account (sandbox/staging/uat/production)"
  type        = string
}

variable "domain_name" {
  description = "Domain name for Route53 hosted zone"
  type        = string
}

variable "shared_services_account_id" {
  description = "AWS account ID for shared-services (Route53, state backend)"
  type        = string
  default     = "088994864650"
}

variable "shared_services_role_name" {
  description = "IAM role name for shared-services cross-account access"
  type        = string
  default     = "terraform"
}