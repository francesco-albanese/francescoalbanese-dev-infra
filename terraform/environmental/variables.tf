variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "account_id" {
  description = "AWS account ID (shared-services)"
  type        = string
  default     = "088994864650"
}

variable "account_name" {
  description = "Account name"
  type        = string
  default     = "shared-services"
}

variable "domain_name" {
  description = "Domain name for Route53 hosted zone"
  type        = string
  default     = "francescoalbanese.dev"
}