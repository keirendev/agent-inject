variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
}

variable "environment" {
  description = "Environment label (lab, dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource references"
  type        = string
}

variable "customers_table_name" {
  description = "Name of the DynamoDB customers table"
  type        = string
}

variable "customers_table_arn" {
  description = "ARN of the DynamoDB customers table"
  type        = string
}

variable "kb_bucket_name" {
  description = "Name of the S3 knowledge base bucket"
  type        = string
}

variable "kb_bucket_arn" {
  description = "ARN of the S3 knowledge base bucket"
  type        = string
}

variable "enable_overpermissive_iam" {
  description = "When true, Lambda gets broad IAM permissions instead of least-privilege"
  type        = bool
  default     = false
}
