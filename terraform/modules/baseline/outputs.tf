output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.main.arn
}

output "log_bucket_name" {
  description = "Name of the CloudTrail log bucket"
  value       = aws_s3_bucket.cloudtrail_logs.id
}

output "lab_admin_role_arn" {
  description = "ARN of the lab-admin IAM role"
  value       = aws_iam_role.lab_admin.arn
}
