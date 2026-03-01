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

variable "kb_bucket_name" {
  description = "Name of the S3 knowledge base documents bucket"
  type        = string
}

variable "kb_bucket_arn" {
  description = "ARN of the S3 knowledge base documents bucket"
  type        = string
}

variable "kb_include_internal_docs" {
  description = "When true, KB indexes the entire S3 bucket including internal/ docs (enables RAG poisoning)"
  type        = bool
  default     = false
}
