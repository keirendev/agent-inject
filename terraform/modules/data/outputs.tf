output "kb_bucket_name" {
  description = "Name of the knowledge base documents S3 bucket"
  value       = aws_s3_bucket.kb_docs.id
}

output "kb_bucket_arn" {
  description = "ARN of the knowledge base documents S3 bucket"
  value       = aws_s3_bucket.kb_docs.arn
}

output "customers_table_name" {
  description = "Name of the customers DynamoDB table"
  value       = aws_dynamodb_table.customers.name
}

output "customers_table_arn" {
  description = "ARN of the customers DynamoDB table"
  value       = aws_dynamodb_table.customers.arn
}
