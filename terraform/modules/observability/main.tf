# =============================================================================
# Observability Module
#
# Enables Bedrock model invocation logging (request/response payloads to S3
# and CloudWatch) and creates a CloudWatch dashboard for monitoring agent
# activity, guardrail interventions, Lambda tool calls, and error rates.
#
# CloudTrail and Lambda log groups are handled by the baseline and agent-tools
# modules respectively — this module adds what's missing.
# =============================================================================

locals {
  prefix                = "${var.project_name}-${var.environment}"
  lambda_log_group_name = "/aws/lambda/${var.lambda_function_name}"
}

data "aws_caller_identity" "current" {}

# =============================================================================
# S3 Bucket — Bedrock model invocation logs
# =============================================================================

resource "aws_s3_bucket" "invocation_logs" {
  bucket        = "${local.prefix}-bedrock-invocation-logs"
  force_destroy = true # Lab environment — allow easy teardown

  tags = {
    Name = "${local.prefix}-bedrock-invocation-logs"
  }
}

resource "aws_s3_bucket_versioning" "invocation_logs" {
  bucket = aws_s3_bucket.invocation_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "invocation_logs" {
  bucket = aws_s3_bucket.invocation_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_policy" "invocation_logs" {
  bucket = aws_s3_bucket.invocation_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockLogsWrite"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.invocation_logs.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# =============================================================================
# CloudWatch Log Group — Bedrock model invocation logs
# =============================================================================

resource "aws_cloudwatch_log_group" "bedrock_invocation" {
  name              = "/aws/bedrock/${local.prefix}-invocation-logs"
  retention_in_days = 14

  tags = {
    Name = "${local.prefix}-bedrock-invocation-logs"
  }
}

# =============================================================================
# IAM Role — Bedrock service role for CloudWatch log delivery
# =============================================================================

resource "aws_iam_role" "bedrock_logging" {
  name = "${local.prefix}-bedrock-logging-role"

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
    Name = "${local.prefix}-bedrock-logging-role"
  }
}

resource "aws_iam_role_policy" "bedrock_logging" {
  name = "${local.prefix}-bedrock-logging"
  role = aws_iam_role.bedrock_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.bedrock_invocation.arn}:*"
      }
    ]
  })
}

# =============================================================================
# Bedrock Model Invocation Logging Configuration
#
# Account-level singleton (one per region). Enables full request/response
# logging for all Bedrock model invocations to both S3 and CloudWatch.
# =============================================================================

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  logging_config {
    embedding_data_delivery_enabled = true
    image_data_delivery_enabled     = true
    text_data_delivery_enabled      = true

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocation.name
      role_arn       = aws_iam_role.bedrock_logging.arn

      large_data_delivery_s3_config {
        bucket_name = aws_s3_bucket.invocation_logs.id
        key_prefix  = "large-data"
      }
    }

    s3_config {
      bucket_name = aws_s3_bucket.invocation_logs.id
      key_prefix  = "AWSLogs/${data.aws_caller_identity.current.account_id}/BedrockModelInvocationLogs"
    }
  }

  depends_on = [
    aws_s3_bucket_policy.invocation_logs,
    aws_iam_role_policy.bedrock_logging,
  ]
}

# =============================================================================
# CloudWatch Dashboard
#
# 8 widgets across 4 rows: agent invocations, errors, guardrail metrics,
# Lambda/tool metrics, latency, and token usage.
# =============================================================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.prefix}-agent-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # --- Row 1: Agent invocation overview ---
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Agent Invocation Count"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Sum"
          period  = 300
          metrics = [
            ["AWS/Bedrock/Agents", "Invocations", "AgentAliasArn", var.agent_alias_arn]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Agent Errors"
          view    = "timeSeries"
          stacked = true
          region  = var.aws_region
          stat    = "Sum"
          period  = 300
          metrics = [
            ["AWS/Bedrock/Agents", "InvocationClientErrors", "AgentAliasArn", var.agent_alias_arn],
            [".", "InvocationServerErrors", ".", "."],
            [".", "InvocationThrottles", ".", "."]
          ]
        }
      },

      # --- Row 2: Guardrail metrics ---
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Guardrail Invocations vs Interventions"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Sum"
          period  = 300
          metrics = [
            ["AWS/Bedrock/Guardrails", "Invocations", "GuardrailArn", var.guardrail_arn],
            [".", "InvocationsIntervened", ".", "."]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Guardrail Interventions by Policy Type"
          view    = "timeSeries"
          stacked = true
          region  = var.aws_region
          stat    = "Sum"
          period  = 300
          metrics = [
            ["AWS/Bedrock/Guardrails", "InvocationsIntervened", "GuardrailArn", var.guardrail_arn, "GuardrailPolicyType", "ContentPolicy"],
            ["...", "TopicPolicy"],
            ["...", "SensitiveInformationPolicy"]
          ]
        }
      },

      # --- Row 3: Lambda / Tool call metrics ---
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Invocations & Errors"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Sum"
          period  = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Throttles", ".", "."]
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Tool Call Frequency by Function"
          region = var.aws_region
          query  = "SOURCE '${local.lambda_log_group_name}' | filter @message like /Tool invocation: function=/ | parse @message 'Tool invocation: function=* parameters=*' as tool_name, params | stats count(*) as call_count by tool_name | sort call_count desc"
          view   = "table"
        }
      },

      # --- Row 4: Latency and token usage ---
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title   = "Agent Latency (p50, p90, p99)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["AWS/Bedrock/Agents", "Latency", "AgentAliasArn", var.agent_alias_arn, { stat = "p50" }],
            ["...", { stat = "p90" }],
            ["...", { stat = "p99" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title   = "Model Token Usage"
          view    = "timeSeries"
          stacked = true
          region  = var.aws_region
          stat    = "Sum"
          period  = 300
          metrics = [
            ["AWS/Bedrock/Agents", "InputTokenCount", "AgentAliasArn", var.agent_alias_arn],
            [".", "OutputTokenCount", ".", "."]
          ]
        }
      }
    ]
  })
}
