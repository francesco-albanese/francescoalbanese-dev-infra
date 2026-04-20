variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "account_name" {
  description = "Account name (sandbox/staging/uat/production)"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for ECR repositories"
  type        = string
  default     = "francescoalbanese-dev"
}
