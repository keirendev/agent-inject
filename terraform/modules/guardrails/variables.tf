# -----------------------------------------------------------------------------
# Guardrails module variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
}

variable "environment" {
  description = "Environment label (lab, dev, prod)"
  type        = string
}

variable "guardrail_sensitivity" {
  description = "Filter strength for content filters and prompt attack detection (HIGH/MEDIUM/LOW/NONE)"
  type        = string
  default     = "HIGH"

  validation {
    condition     = contains(["HIGH", "MEDIUM", "LOW", "NONE"], var.guardrail_sensitivity)
    error_message = "guardrail_sensitivity must be one of: HIGH, MEDIUM, LOW, NONE"
  }
}

variable "enable_topic_policies" {
  description = "Whether to include denied topic policies (Competitor Products, Internal System Information). Disable for attack scenarios where topic policies would block the demonstrated attacks."
  type        = bool
  default     = true
}
