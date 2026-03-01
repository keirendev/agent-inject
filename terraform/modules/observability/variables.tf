# -----------------------------------------------------------------------------
# Observability module variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
}

variable "environment" {
  description = "Environment label (lab, dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "agent_alias_arn" {
  description = "ARN of the Bedrock Agent PROD alias (CloudWatch metric dimension)"
  type        = string
}

variable "guardrail_arn" {
  description = "ARN of the Bedrock Guardrail (CloudWatch metric dimension)"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the agent tools Lambda function (for dashboard metrics)"
  type        = string
}
