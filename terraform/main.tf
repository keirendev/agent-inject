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

# --- S3 bucket for KB docs, DynamoDB for customer records ---
module "data" {
  source = "./modules/data"

  project_name = var.project_name
  environment  = var.environment
}

# --- Lambda function backing the Bedrock Agent Action Group ---
module "agent_tools" {
  source = "./modules/agent-tools"

  project_name             = var.project_name
  environment              = var.environment
  aws_region               = var.aws_region
  customers_table_name     = module.data.customers_table_name
  customers_table_arn      = module.data.customers_table_arn
  kb_bucket_name           = module.data.kb_bucket_name
  kb_bucket_arn            = module.data.kb_bucket_arn
  enable_overpermissive_iam = var.enable_overpermissive_iam
}

# --- OpenSearch Serverless + Bedrock Knowledge Base ---
module "knowledge_base" {
  source = "./modules/knowledge-base"

  project_name             = var.project_name
  environment              = var.environment
  aws_region               = var.aws_region
  kb_bucket_name           = module.data.kb_bucket_name
  kb_bucket_arn            = module.data.kb_bucket_arn
  kb_include_internal_docs = var.kb_include_internal_docs
}

# --- Bedrock Agent (orchestrator + system prompt) ---
module "agent" {
  source = "./modules/agent"

  project_name               = var.project_name
  environment                = var.environment
  aws_region                 = var.aws_region
  lambda_arn                 = module.agent_tools.lambda_arn
  lambda_function_name       = module.agent_tools.lambda_function_name
  knowledge_base_id          = module.knowledge_base.knowledge_base_id
  use_weak_system_prompt     = var.use_weak_system_prompt
  enable_refund_confirmation = var.enable_refund_confirmation
  enable_excessive_tools     = var.enable_excessive_tools
}

# --- Future modules (uncomment as built) ---
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
