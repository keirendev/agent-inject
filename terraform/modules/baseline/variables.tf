variable "project_name" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment label"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used in CloudTrail bucket policy)"
  type        = string
}

variable "alert_email" {
  description = "Email address for budget alert notifications"
  type        = string
}
