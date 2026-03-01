# --- Baseline ---

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = module.baseline.cloudtrail_arn
}

output "cloudtrail_log_bucket" {
  description = "S3 bucket storing CloudTrail logs"
  value       = module.baseline.log_bucket_name
}

output "lab_admin_role_arn" {
  description = "ARN of the lab-admin IAM role"
  value       = module.baseline.lab_admin_role_arn
}

# --- Networking ---

output "vpc_id" {
  description = "ID of the lab VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

output "frontend_sg_id" {
  description = "Security group ID for frontend (operator IP only)"
  value       = module.networking.frontend_sg_id
}

output "internal_sg_id" {
  description = "Security group ID for internal resources"
  value       = module.networking.internal_sg_id
}

# --- Data ---

output "kb_bucket_name" {
  description = "S3 bucket for knowledge base documents"
  value       = module.data.kb_bucket_name
}

output "customers_table_name" {
  description = "DynamoDB table for customer records"
  value       = module.data.customers_table_name
}

# --- Agent Tools ---

output "agent_tools_lambda_arn" {
  description = "ARN of the agent tools Lambda function"
  value       = module.agent_tools.lambda_arn
}

output "agent_tools_lambda_name" {
  description = "Name of the agent tools Lambda function"
  value       = module.agent_tools.lambda_function_name
}

output "agent_tools_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.agent_tools.lambda_role_arn
}
