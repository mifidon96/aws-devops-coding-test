variable "name_prefix" {
  description = "Prefix applied to all resource names."
  type        = string
}

variable "github_org" {
  description = "GitHub organisation or username that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "Repository name."
  type        = string
}

variable "allowed_branch" {
  description = "The only branch permitted to assume the deploy role."
  type        = string
  default     = "main"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one - only one per URL is allowed per account."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of a pre-existing GitHub OIDC provider, required when create_oidc_provider is false."
  type        = string
  default     = null
}

variable "lambda_function_name" {
  description = "The one function the deploy role is permitted to update."
  type        = string
}

variable "aws_region" {
  description = "Region the Lambda lives in, used to build its ARN."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
