output "lambda_arn" {
  description = "ARN of the agent tools Lambda function"
  value       = aws_lambda_function.agent_tools.arn
}

output "lambda_function_name" {
  description = "Name of the agent tools Lambda function"
  value       = aws_lambda_function.agent_tools.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}
