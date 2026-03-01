# -----------------------------------------------------------------------------
# Agent module - Bedrock Agent with Action Group + Knowledge Base
#
# Creates:
#   - IAM role for the agent (bedrock:InvokeModel, bedrock:Retrieve)
#   - Lambda permission for Bedrock to invoke agent tools
#   - Bedrock Agent with system prompt (secure or weak variant)
#   - Action Group connecting to Lambda tools via OpenAPI spec
#   - Knowledge Base association for RAG retrieval
#   - Agent alias for stable invocation endpoint
#
# The use_weak_system_prompt toggle selects between the hardened and
# deliberately vague system prompts — demonstrating how prompt design
# directly affects vulnerability to prompt injection.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  agent_name = "${var.project_name}-${var.environment}-support-agent"

  # Select system prompt based on scenario toggle
  system_prompt = var.use_weak_system_prompt ? (
    file("${path.module}/../../../prompts/system-prompt-weak.txt")
  ) : (
    file("${path.module}/../../../prompts/system-prompt-secure.txt")
  )
}

# =============================================================================
# IAM Role for Bedrock Agent
# =============================================================================

resource "aws_iam_role" "agent_role" {
  name = "${local.agent_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = {
    Name = "${local.agent_name}-role"
  }
}

resource "aws_iam_role_policy" "agent_permissions" {
  name = "${local.agent_name}-permissions"
  role = aws_iam_role.agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeFoundationModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = "arn:aws:bedrock:${data.aws_region.current.id}::foundation-model/${var.foundation_model}"
      },
      {
        Sid    = "RetrieveFromKnowledgeBase"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
        ]
        Resource = "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:knowledge-base/${var.knowledge_base_id}"
      },
    ]
  })
}

# =============================================================================
# Lambda Permission - allow Bedrock to invoke the agent tools Lambda
# =============================================================================

resource "aws_lambda_permission" "allow_bedrock" {
  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:agent/*"
}

# =============================================================================
# Bedrock Agent
# =============================================================================

resource "aws_bedrockagent_agent" "support_agent" {
  agent_name                  = local.agent_name
  agent_resource_role_arn     = aws_iam_role.agent_role.arn
  foundation_model            = var.foundation_model
  instruction                 = local.system_prompt
  idle_session_ttl_in_seconds = 900
  prepare_agent               = false # Prepare explicitly after action group + KB

  guardrail_configuration {
    guardrail_identifier = var.guardrail_id
    guardrail_version    = var.guardrail_version
  }

  tags = {
    Name = local.agent_name
  }
}

# =============================================================================
# Action Group - connects Lambda tools via OpenAPI spec
# =============================================================================

resource "aws_bedrockagent_agent_action_group" "customer_tools" {
  agent_id          = aws_bedrockagent_agent.support_agent.agent_id
  agent_version     = "DRAFT"
  action_group_name = "${var.project_name}-${var.environment}-customer-tools"

  action_group_executor {
    lambda = var.lambda_arn
  }

  api_schema {
    payload = file("${path.module}/../../../src/lambda/agent_tools/openapi.yaml")
  }
}

# =============================================================================
# Knowledge Base Association
# =============================================================================

resource "aws_bedrockagent_agent_knowledge_base_association" "kb" {
  agent_id             = aws_bedrockagent_agent.support_agent.agent_id
  knowledge_base_id    = var.knowledge_base_id
  knowledge_base_state = "ENABLED"
  description          = "NovaCrest product documentation and support policies. Use this to answer questions about features, pricing, SLAs, refund policies, and integrations."
}

# =============================================================================
# Prepare Agent - must run after action group and KB association
# =============================================================================

resource "null_resource" "prepare_agent" {
  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agent prepare-agent \
        --agent-id ${aws_bedrockagent_agent.support_agent.agent_id} \
        --region ${data.aws_region.current.id}

      echo "Waiting for agent to reach PREPARED state..."
      for i in $(seq 1 30); do
        STATUS=$(aws bedrock-agent get-agent \
          --agent-id ${aws_bedrockagent_agent.support_agent.agent_id} \
          --region ${data.aws_region.current.id} \
          --query 'agent.agentStatus' --output text)
        echo "Attempt $i/30: Status = $STATUS"
        if [ "$STATUS" = "PREPARED" ]; then
          echo "Agent is PREPARED"
          exit 0
        fi
        sleep 5
      done
      echo "ERROR: Agent did not reach PREPARED state in time"
      exit 1
    EOT
  }

  triggers = {
    agent_id         = aws_bedrockagent_agent.support_agent.agent_id
    action_group_id  = aws_bedrockagent_agent_action_group.customer_tools.action_group_id
    kb_association   = aws_bedrockagent_agent_knowledge_base_association.kb.knowledge_base_id
  }

  depends_on = [
    aws_bedrockagent_agent_action_group.customer_tools,
    aws_bedrockagent_agent_knowledge_base_association.kb,
  ]
}

# =============================================================================
# Agent Alias - stable endpoint for invocation
# =============================================================================

resource "aws_bedrockagent_agent_alias" "prod" {
  agent_id           = aws_bedrockagent_agent.support_agent.agent_id
  agent_alias_name   = "PROD"

  depends_on = [null_resource.prepare_agent]

  tags = {
    Name = "${local.agent_name}-prod-alias"
  }
}
