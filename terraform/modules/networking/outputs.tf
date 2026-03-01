output "vpc_id" {
  description = "ID of the lab VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "frontend_sg_id" {
  description = "Security group ID for frontend resources (operator IP access)"
  value       = aws_security_group.frontend.id
}

output "internal_sg_id" {
  description = "Security group ID for internal resources (egress only)"
  value       = aws_security_group.internal.id
}
