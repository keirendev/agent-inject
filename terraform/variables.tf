# -----------------------------------------------------------------------------
# Core variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "novacrest"
}

variable "environment" {
  description = "Environment label (lab, dev, prod)"
  type        = string
  default     = "lab"
}

variable "operator_ip" {
  description = "Your public IP address — all ingress is restricted to this IP. Get it with: curl -s https://checkip.amazonaws.com"
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.operator_ip))
    error_message = "operator_ip must be a valid IPv4 address (e.g., 203.0.113.42)"
  }
}

variable "alert_email" {
  description = "Email address for budget and billing alert notifications"
  type        = string
}

# -----------------------------------------------------------------------------
# Scenario toggle variables
# These control which misconfigurations are active. The secure baseline has
# everything locked down. Each attack scenario .tfvars flips specific toggles.
# -----------------------------------------------------------------------------

variable "enable_overpermissive_iam" {
  description = "When true, Lambda IAM role gets broad permissions instead of least-privilege"
  type        = bool
  default     = false
}

variable "guardrail_sensitivity" {
  description = "Bedrock Guardrail prompt attack detection sensitivity (HIGH = secure, NONE = disabled)"
  type        = string
  default     = "HIGH"

  validation {
    condition     = contains(["HIGH", "MEDIUM", "LOW", "NONE"], var.guardrail_sensitivity)
    error_message = "guardrail_sensitivity must be one of: HIGH, MEDIUM, LOW, NONE"
  }
}

variable "kb_include_internal_docs" {
  description = "When true, internal HR/engineering docs are included in the knowledge base (enables RAG poisoning)"
  type        = bool
  default     = false
}

variable "enable_refund_confirmation" {
  description = "When true, agent asks user to confirm before processing refunds"
  type        = bool
  default     = true
}

variable "use_weak_system_prompt" {
  description = "When true, uses the vague system prompt that lacks security boundaries"
  type        = bool
  default     = false
}

variable "enable_excessive_tools" {
  description = "When true, agent gets additional tools beyond what's needed (increases attack surface)"
  type        = bool
  default     = false
}

variable "enable_topic_policies" {
  description = "When true, guardrail includes denied topic policies (Competitor Products, Internal System Information). Disable for attack scenarios where these would block demonstrated attacks."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Model selection
# -----------------------------------------------------------------------------

variable "foundation_model" {
  description = "Bedrock foundation model ID for the agent (e.g., amazon.nova-lite-v1:0, amazon.nova-micro-v1:0, amazon.nova-pro-v1:0)"
  type        = string
  default     = "amazon.nova-lite-v1:0"
}
