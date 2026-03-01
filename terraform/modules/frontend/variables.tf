# -----------------------------------------------------------------------------
# Frontend module variables
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

variable "vpc_id" {
  description = "VPC ID for the EC2 instance"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for the EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID (frontend SG with operator IP only)"
  type        = string
}

variable "agent_id" {
  description = "Bedrock Agent ID"
  type        = string
}

variable "agent_alias_id" {
  description = "Bedrock Agent Alias ID"
  type        = string
}

variable "frontend_password" {
  description = "Password for the frontend login page"
  type        = string
  default     = "novacrest-lab"
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
