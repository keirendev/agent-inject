output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.kb.id
}

output "knowledge_base_arn" {
  description = "ARN of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.kb.arn
}

output "data_source_ids" {
  description = "IDs of the Bedrock KB data sources (secure or vulnerable depending on toggle)"
  value = var.kb_include_internal_docs ? (
    [for ds in aws_bedrockagent_data_source.vulnerable : ds.data_source_id]
  ) : (
    [for ds in aws_bedrockagent_data_source.secure : ds.data_source_id]
  )
}

output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.kb.arn
}

output "opensearch_collection_endpoint" {
  description = "Endpoint URL of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.kb.collection_endpoint
}
