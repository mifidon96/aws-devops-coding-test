variable "name_prefix" {
  description = "Prefix applied to all resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the instance lives in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "RDS requires a subnet group spanning at least two Availability Zones."
  }
}

variable "engine" {
  description = <<-EOT
    RDS SQL Server edition.
      sqlserver-ex  Express  - free licence, supports db.t3.*, no Multi-AZ
      sqlserver-web Web      - supports db.t3.*, web-facing workloads only
      sqlserver-se  Standard - Multi-AZ capable, requires db.m*/db.r* classes
      sqlserver-ee  Enterprise
  EOT
  type        = string
  default     = "sqlserver-ex"

  validation {
    condition     = contains(["sqlserver-ex", "sqlserver-web", "sqlserver-se", "sqlserver-ee"], var.engine)
    error_message = "engine must be one of sqlserver-ex, sqlserver-web, sqlserver-se, sqlserver-ee."
  }
}

variable "instance_class" {
  description = "RDS instance class. db.t3.medium per the brief - valid on Express/Web editions only."
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Storage in GiB. 20 is the RDS minimum for gp3."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling."
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Enable Multi-AZ. Not supported on Express Edition - guarded by a precondition."
  type        = bool
  default     = false
}

variable "master_username" {
  description = "Master username. 'admin' and 'sa' are reserved and rejected by RDS."
  type        = string
  default     = "dbadmin"
}

variable "db_port" {
  description = "TDS port."
  type        = number
  default     = 1433
}

variable "allowed_source_security_group_ids" {
  description = "Security groups permitted to reach the database. Populated with the Lambda SG in stage 5."
  type        = list(string)
  default     = []
}

variable "kms_key_id" {
  description = "Customer-managed KMS key ARN. Null uses the AWS-managed key."
  type        = string
  default     = null
}

variable "secret_recovery_window_in_days" {
  description = "Secrets Manager recovery window. 0 deletes immediately - dev only."
  type        = number
  default     = 0
}

variable "backup_retention_period" {
  description = "Automated backup retention in days."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Block accidental deletion. Should be true outside dev."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. True for dev only."
  type        = bool
  default     = true
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Log types to ship to CloudWatch. SQL Server supports 'error' and 'agent'."
  type        = list(string)
  default     = ["error"]
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
