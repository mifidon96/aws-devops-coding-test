variable "name_prefix" {
  description = "Prefix applied to all resource names."
  type        = string
}

variable "source_dir" {
  description = "Path to the application source directory, packaged on the initial apply."
  type        = string
}

variable "vpc_id" {
  description = "VPC the Lambda ENIs attach to."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR, used for the HTTPS egress rule to VPC endpoints."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the Lambda ENIs."
  type        = list(string)
}

variable "database_security_group_id" {
  description = "Database security group the Lambda is allowed egress to."
  type        = string
}

variable "db_port" {
  description = "TDS port."
  type        = number
  default     = 1433
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the DB credentials."
  type        = string
}

variable "db_secret_name" {
  description = "Name of the secret, passed to the function as an environment variable."
  type        = string
}

variable "db_name" {
  description = "Logical database the application uses. 'master' until a real one is created post-provision."
  type        = string
  default     = "master"
}

variable "memory_size" {
  description = "Memory in MB. CPU scales with it."
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Timeout in seconds. API Gateway caps integrations at 30s regardless."
  type        = number
  default     = 30
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
