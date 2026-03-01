variable "project_name" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment label"
  type        = string
}

variable "operator_ip_cidr" {
  description = "Operator's IP as a /32 CIDR block for security group rules"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to use (2 is sufficient for a lab)"
  type        = list(string)
}
