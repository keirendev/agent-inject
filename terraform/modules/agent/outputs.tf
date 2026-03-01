output "agent_id" {
  description = "ID of the Bedrock Agent"
  value       = aws_bedrockagent_agent.support_agent.agent_id
}

output "agent_arn" {
  description = "ARN of the Bedrock Agent"
  value       = aws_bedrockagent_agent.support_agent.agent_arn
}

output "agent_alias_id" {
  description = "ID of the PROD agent alias (use this to invoke the agent)"
  value       = aws_bedrockagent_agent_alias.prod.agent_alias_id
}

output "agent_alias_arn" {
  description = "ARN of the PROD agent alias"
  value       = aws_bedrockagent_agent_alias.prod.agent_alias_arn
}
