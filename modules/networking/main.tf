###############################################################################
# Networking
#
# RDS and Lambda both sit in private subnets. Nothing holding data is
# internet-reachable. No NAT Gateway by default: the only outbound call the
# application makes is to Secrets Manager, served by an Interface VPC Endpoint.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  tags = merge(var.tags, { Module = "networking" })
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # enable_dns_support   -> the VPC resolver answers queries at all
  # enable_dns_hostnames -> private DNS names get assigned
  # BOTH are required for Interface VPC Endpoints and RDS private DNS.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-igw" })
}

###############################################################################
# Subnets
#
# /16 carved into /24s. Public at offset 0, private at offset 10 — the gap
# leaves room for a future tier (e.g. dedicated DB subnets) without renumbering
# anything that already exists.
###############################################################################

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

###############################################################################
# Routing
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table PER AZ. Looks redundant with no NAT, but it is what
# makes single_nat_gateway = false a variable change rather than a rewrite.
resource "aws_route_table" "private" {
  count = var.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-rt-private-${local.azs[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

###############################################################################
# Optional NAT Gateway
#
# Off by default. Enable only if the workload later needs to reach third-party
# endpoints on the public internet. Routes are already wired, so it is a
# variable change rather than a rewrite.
###############################################################################

locals {
  nat_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : var.az_count) : 0
}

resource "aws_eip" "nat" {
  count = local.nat_count

  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.name_prefix}-eip-nat-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, { Name = "${var.name_prefix}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? var.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
}

###############################################################################
# VPC Endpoints
#
# secretsmanager (Interface) -> DNS + ENI, removes the need for a NAT Gateway
# s3 (Gateway)               -> route table entry, no hourly charge
###############################################################################

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name_prefix}-vpce-sg"
  description = "HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpce-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from inside the VPC"
  cidr_ipv4         = aws_vpc.this.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  # Without this the SDK resolves the PUBLIC endpoint and, with no NAT, the
  # Lambda hangs until timeout with no useful error.
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpce-secretsmanager" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpce-s3" })
}
