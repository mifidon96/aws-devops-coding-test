variable "project" {
  description = "Project name, used as a resource name prefix."
  type        = string
  default     = "nodeapi"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "Target AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "github_org" {
  description = "GitHub username or organisation - scopes the OIDC trust policy to your repo."
  type        = string
}

variable "github_repo" {
  description = "Repository name."
  type        = string
  default     = "aws-devops-coding-test"
}

variable "create_oidc_provider" {
  description = "Set false if the account already has a GitHub OIDC provider (aws iam list-open-id-connect-providers)."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of the pre-existing GitHub OIDC provider, used when create_oidc_provider is false."
  type        = string
  default     = null
}
