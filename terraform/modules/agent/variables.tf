# -----------------------------------------------------------------------------
# Agent module variables
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

variable "foundation_model" {
  description = "Bedrock foundation model ID for the agent"
  type        = string
  default     = "amazon.nova-lite-v1:0"
}

variable "lambda_arn" {
  description = "ARN of the agent tools Lambda function"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the agent tools Lambda function"
  type        = string
}

variable "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base"
  type        = string
}

variable "guardrail_id" {
  description = "ID of the Bedrock Guardrail to associate with the agent"
  type        = string
}

variable "guardrail_version" {
  description = "Published version number of the guardrail"
  type        = string
}

variable "use_weak_system_prompt" {
  description = "When true, uses the vague system prompt that lacks security boundaries"
  type        = bool
  default     = false
}

variable "enable_refund_confirmation" {
  description = "When true, agent asks user to confirm before processing refunds (enforced via system prompt)"
  type        = bool
  default     = true
}

variable "enable_excessive_tools" {
  description = "When true, agent gets additional tools beyond what's needed (Phase 2)"
  type        = bool
  default     = false
}
