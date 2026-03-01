output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "URL to the CloudWatch dashboard in the AWS Console"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "invocation_log_group_name" {
  description = "CloudWatch log group for Bedrock model invocation logs"
  value       = aws_cloudwatch_log_group.bedrock_invocation.name
}

output "invocation_log_bucket_name" {
  description = "S3 bucket storing Bedrock model invocation logs"
  value       = aws_s3_bucket.invocation_logs.id
}
