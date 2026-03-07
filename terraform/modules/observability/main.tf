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
# SNS Topic — Security Alerts
# =============================================================================

resource "aws_sns_topic" "security_alerts" {
  name = "${local.prefix}-security-alerts"

  tags = {
    Name = "${local.prefix}-security-alerts"
  }
}

resource "aws_sns_topic_subscription" "alert_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# =============================================================================
# CloudWatch Metric Filters — Extract security events from Lambda logs
#
# These create custom metrics in the NovaCrest/AgentSecurity namespace from
# structured log output in the agent tools Lambda.
# =============================================================================

resource "aws_cloudwatch_log_metric_filter" "send_email_calls" {
  name           = "${local.prefix}-send-email-calls"
  log_group_name = local.lambda_log_group_name
  pattern        = "\"SIMULATED EMAIL SENT\""

  metric_transformation {
    name          = "SendEmailCalls"
    namespace     = "NovaCrest/AgentSecurity"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "run_internal_query_calls" {
  name           = "${local.prefix}-run-internal-query-calls"
  log_group_name = local.lambda_log_group_name
  pattern        = "\"INTERNAL QUERY EXECUTED\""

  metric_transformation {
    name          = "RunInternalQueryCalls"
    namespace     = "NovaCrest/AgentSecurity"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "update_customer_record_calls" {
  name           = "${local.prefix}-update-customer-record-calls"
  log_group_name = local.lambda_log_group_name
  pattern        = "\"function=update_customer_record\""

  metric_transformation {
    name          = "UpdateCustomerRecordCalls"
    namespace     = "NovaCrest/AgentSecurity"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "process_refund_calls" {
  name           = "${local.prefix}-process-refund-calls"
  log_group_name = local.lambda_log_group_name
  pattern        = "\"function=process_refund\""

  metric_transformation {
    name          = "ProcessRefundCalls"
    namespace     = "NovaCrest/AgentSecurity"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "lookup_customer_calls" {
  name           = "${local.prefix}-lookup-customer-calls"
  log_group_name = local.lambda_log_group_name
  pattern        = "\"function=lookup_customer\""

  metric_transformation {
    name          = "LookupCustomerCalls"
    namespace     = "NovaCrest/AgentSecurity"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "tool_errors" {
  name           = "${local.prefix}-tool-errors"
  log_group_name = local.lambda_log_group_name
  pattern        = "?\"Error executing\" ?\"Unknown function\""

  metric_transformation {
    name          = "ToolErrors"
    namespace     = "NovaCrest/AgentSecurity"
    value         = "1"
    default_value = "0"
  }
}

# =============================================================================
# CloudWatch Alarms — Security event detection
#
# All alarms notify the security alerts SNS topic. treat_missing_data is set to
# notBreaching because the lab is frequently torn down and rebuilt.
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "guardrail_intervention_spike" {
  alarm_name          = "${local.prefix}-guardrail-intervention-spike"
  alarm_description   = "HIGH: >5 guardrail interventions in 5min — active prompt injection attempt"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "InvocationsIntervened"
  namespace           = "AWS/Bedrock/Guardrails"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  dimensions = {
    GuardrailArn = var.guardrail_arn
  }

  tags = { Severity = "HIGH" }
}

resource "aws_cloudwatch_metric_alarm" "content_policy_triggered" {
  alarm_name          = "${local.prefix}-content-policy-triggered"
  alarm_description   = "MEDIUM: >2 content policy interventions in 5min — jailbreak attempt"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "InvocationsIntervened"
  namespace           = "AWS/Bedrock/Guardrails"
  period              = 300
  statistic           = "Sum"
  threshold           = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  dimensions = {
    GuardrailArn       = var.guardrail_arn
    GuardrailPolicyType = "ContentPolicy"
  }

  tags = { Severity = "MEDIUM" }
}

resource "aws_cloudwatch_metric_alarm" "send_email_invoked" {
  alarm_name          = "${local.prefix}-send-email-invoked"
  alarm_description   = "CRITICAL: send_email tool invoked — data exfiltration via excessive tool"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SendEmailCalls"
  namespace           = "NovaCrest/AgentSecurity"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = { Severity = "CRITICAL" }
}

resource "aws_cloudwatch_metric_alarm" "internal_query_invoked" {
  alarm_name          = "${local.prefix}-internal-query-invoked"
  alarm_description   = "CRITICAL: run_internal_query tool invoked — excessive tool abuse"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RunInternalQueryCalls"
  namespace           = "NovaCrest/AgentSecurity"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = { Severity = "CRITICAL" }
}

resource "aws_cloudwatch_metric_alarm" "update_customer_invoked" {
  alarm_name          = "${local.prefix}-update-customer-invoked"
  alarm_description   = "CRITICAL: update_customer_record tool invoked — unauthorized data modification"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UpdateCustomerRecordCalls"
  namespace           = "NovaCrest/AgentSecurity"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = { Severity = "CRITICAL" }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  alarm_name          = "${local.prefix}-lambda-error-rate"
  alarm_description   = "MEDIUM: >3 Lambda errors in 5min — tool manipulation or malformed inputs"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  tags = { Severity = "MEDIUM" }
}

resource "aws_cloudwatch_metric_alarm" "refund_frequency" {
  alarm_name          = "${local.prefix}-refund-frequency"
  alarm_description   = "HIGH: >5 refund processing calls in 5min — automated refund abuse"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ProcessRefundCalls"
  namespace           = "NovaCrest/AgentSecurity"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = { Severity = "HIGH" }
}

resource "aws_cloudwatch_metric_alarm" "customer_enumeration" {
  alarm_name          = "${local.prefix}-customer-enumeration"
  alarm_description   = "HIGH: >10 customer lookups in 5min — data enumeration attack"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "LookupCustomerCalls"
  namespace           = "NovaCrest/AgentSecurity"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = { Severity = "HIGH" }
}

# =============================================================================
# CloudWatch Dashboard
#
# 10 widgets across 5 rows: agent invocations, errors, guardrail metrics,
# Lambda/tool metrics, latency, token usage, and security events.
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
      },

      # --- Row 5: Security events ---
      {
        type   = "log"
        x      = 0
        y      = 24
        width  = 12
        height = 6
        properties = {
          title  = "Suspicious Tool Invocations"
          region = var.aws_region
          query  = "SOURCE '${local.lambda_log_group_name}' | filter @message like /SIMULATED EMAIL SENT/ or @message like /INTERNAL QUERY EXECUTED/ or @message like /function=update_customer_record/ | parse @message 'Tool invocation: function=* parameters=*' as tool_name, params | fields @timestamp, tool_name, params | sort @timestamp desc | limit 20"
          view   = "table"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 24
        width  = 12
        height = 6
        properties = {
          title   = "Customer Lookups per 5min"
          view    = "bar"
          stacked = false
          region  = var.aws_region
          stat    = "Sum"
          period  = 300
          metrics = [
            ["NovaCrest/AgentSecurity", "LookupCustomerCalls"]
          ]
        }
      }
    ]
  })
}
