provider "aws" {
  region = "eu-west-2"
}

module "networking" {
  source = "../../modules/networking"

  name_prefix = "nodeapi-dev"
  vpc_cidr    = "10.20.0.0/16"
  az_count    = 2

  tags = {
    Project     = "nodeapi"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}
