###############################################################################
# Dev environment - wires the four modules together
#
# The Lambda/RDS security group cycle, and how it is broken:
#
#   The Lambda needs egress TO the database SG; the database needs ingress
#   FROM the Lambda SG. If each module referenced the other's SG, Terraform
#   could not order them. So: the database SG is passed INTO the api module
#   (one direction), and the ingress rule on the database is declared HERE in
#   the root module (the other direction), where both SG IDs already exist as
#   module outputs. Standalone rule resources make this possible - inline
#   ingress/egress blocks could not be split this way.
###############################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

###############################################################################
# Networking
###############################################################################

module "networking" {
  source = "../../modules/networking"

  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  az_count    = 2

  # No NAT: Secrets Manager is reached via the Interface VPC Endpoint.
  enable_nat_gateway = false

  tags = local.tags
}

###############################################################################
# Database
###############################################################################

module "database" {
  source = "../../modules/database"

  name_prefix        = local.name_prefix
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids

  # db.t3.medium per the brief - which constrains the edition to Express.
  engine         = "sqlserver-ex"
  instance_class = "db.t3.medium"

  # Dev-only settings, flagged in the README. All flip for production.
  deletion_protection            = false
  skip_final_snapshot            = true
  secret_recovery_window_in_days = 0

  tags = local.tags
}

###############################################################################
# API
###############################################################################

module "api" {
  source = "../../modules/api"

  name_prefix = local.name_prefix
  source_dir  = "${path.root}/../../app"

  vpc_id             = module.networking.vpc_id
  vpc_cidr           = module.networking.vpc_cidr
  private_subnet_ids = module.networking.private_subnet_ids

  database_security_group_id = module.database.security_group_id
  db_secret_arn              = module.database.secret_arn
  db_secret_name             = module.database.secret_name

  tags = local.tags
}

# Completes the security group pair - see the note at the top of this file.
resource "aws_vpc_security_group_ingress_rule" "db_from_lambda" {
  security_group_id            = module.database.security_group_id
  description                  = "TDS from the API Lambda"
  referenced_security_group_id = module.api.security_group_id
  from_port                    = 1433
  to_port                      = 1433
  ip_protocol                  = "tcp"
}

###############################################################################
# Pipeline
###############################################################################

module "pipeline" {
  source = "../../modules/pipeline"

  name_prefix = local.name_prefix

  github_org                 = var.github_org
  github_repo                = var.github_repo
  allowed_branch             = "main"
  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn

  lambda_function_name = module.api.function_name
  aws_region           = var.aws_region

  tags = local.tags
}
