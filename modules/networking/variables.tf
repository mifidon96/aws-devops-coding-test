variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. \"nodeapi-dev\"."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be large enough to carve /24 subnets from."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 8, 0))
    error_message = "vpc_cidr must be a valid CIDR block of /24 or larger (e.g. 10.0.0.0/16)."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to span. RDS subnet groups require at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway(s) for private subnet egress. Default false: Secrets Manager is reached via an Interface VPC Endpoint, so no internet egress is required."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "If NAT is enabled, use one shared NAT Gateway (cheaper) rather than one per AZ (resilient)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
