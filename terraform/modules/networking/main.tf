# -----------------------------------------------------------------------------
# VPC
# Single VPC for the lab. DNS support enabled so private hosted zones and
# VPC endpoints resolve correctly.
# -----------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Subnets — 2 public, 2 private across 2 AZs
# Public: frontend-facing resources (chat UI)
# Private: reserved for future use (Lambda-in-VPC, OpenSearch)
# No NAT gateway — Lambda runs outside VPC to save ~$30/month.
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1) # 10.0.1.0/24, 10.0.2.0/24
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # 10.0.10.0/24, 10.0.11.0/24
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway + Route Tables
# Public subnets route to IGW. Private subnets have local-only routing.
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  # No default route — private subnets have no internet access
  # Use VPC endpoints (below) for AWS service access

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# Security Groups
# frontend: HTTP/HTTPS from operator IP only (the only ingress point)
# internal: egress-only, for resources that don't need inbound access
# -----------------------------------------------------------------------------

resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-${var.environment}-frontend-sg"
  description = "Frontend access restricted to operator IP"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "frontend_https" {
  security_group_id = aws_security_group.frontend.id
  description       = "HTTPS from operator IP"
  cidr_ipv4         = var.operator_ip_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "frontend_http" {
  security_group_id = aws_security_group.frontend.id
  description       = "HTTP from operator IP (redirect to HTTPS)"
  cidr_ipv4         = var.operator_ip_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "frontend_streamlit" {
  security_group_id = aws_security_group.frontend.id
  description       = "Streamlit default port from operator IP"
  cidr_ipv4         = var.operator_ip_cidr
  from_port         = 8501
  to_port           = 8501
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "frontend_all" {
  security_group_id = aws_security_group.frontend.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "internal" {
  name        = "${var.project_name}-${var.environment}-internal-sg"
  description = "Internal resources - egress only, no inbound"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-internal-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "internal_all" {
  security_group_id = aws_security_group.internal.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# VPC Endpoints — free gateway endpoints for S3 and DynamoDB
# Keeps traffic to these services on the AWS backbone instead of going
# through the internet. Associated with private route tables.
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${data.aws_region.current.id}.s3"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${data.aws_region.current.id}.dynamodb"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-dynamodb-endpoint"
  }
}
