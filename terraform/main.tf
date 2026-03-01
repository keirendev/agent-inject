# -----------------------------------------------------------------------------
# Root module — wires together all child modules
# Currently: baseline + networking. More modules added as we build each layer.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  operator_ip_cidr = "${var.operator_ip}/32"
  aws_account_id   = data.aws_caller_identity.current.account_id
  availability_zones = [
    "${var.aws_region}a",
    "${var.aws_region}b",
  ]
}

# --- Account-level security controls ---
module "baseline" {
  source = "./modules/baseline"

  project_name   = var.project_name
  environment    = var.environment
  aws_account_id = local.aws_account_id
  alert_email    = var.alert_email
}

# --- VPC, subnets, security groups ---
module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  operator_ip_cidr   = local.operator_ip_cidr
  availability_zones = local.availability_zones
}

# --- Future modules (uncomment as built) ---
# module "data" {
#   source = "./modules/data"
#   ...
# }
#
# module "agent_tools" {
#   source = "./modules/agent-tools"
#   ...
# }
#
# module "knowledge_base" {
#   source = "./modules/knowledge-base"
#   ...
# }
#
# module "agent" {
#   source = "./modules/agent"
#   ...
# }
#
# module "guardrails" {
#   source = "./modules/guardrails"
#   ...
# }
#
# module "frontend" {
#   source = "./modules/frontend"
#   ...
# }
#
# module "observability" {
#   source = "./modules/observability"
#   ...
# }
