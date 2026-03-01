# -----------------------------------------------------------------------------
# Agent Tools module - Lambda function backing the Bedrock Agent Action Group
#
# Creates:
#   - Lambda function (routes action group calls to tool implementations)
#   - IAM execution role (scoped or overpermissive based on scenario toggle)
#   - CloudWatch log group (14-day retention)
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  function_name = "${var.project_name}-${var.environment}-agent-tools"
  lambda_src    = "${path.module}/../../../src/lambda/agent_tools"
}

# --- Lambda code package ---

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = local.lambda_src
  excludes    = ["__pycache__", "*.pyc", "openapi.yaml", "openapi-extended.yaml", "README.md"]
  output_path = "${path.module}/lambda_package.zip"
}

# --- CloudWatch log group ---

resource "aws_cloudwatch_log_group" "agent_tools" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14

  tags = {
    Name = "${local.function_name}-logs"
  }
}

# --- IAM role for Lambda ---

resource "aws_iam_role" "lambda_role" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.function_name}-role"
  }
}

# Basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy" "lambda_logging" {
  name = "${local.function_name}-logging"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.agent_tools.arn}:*"
      }
    ]
  })
}

# --- Secure IAM policy (least privilege) ---
# Only attached when enable_overpermissive_iam = false

resource "aws_iam_role_policy" "secure_data_access" {
  count = var.enable_overpermissive_iam ? 0 : 1

  name = "${local.function_name}-secure-data"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBReadCustomers"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [
          var.customers_table_arn,
          "${var.customers_table_arn}/index/email-index",
        ]
      },
      {
        Sid    = "S3ReadKBDocs"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = [
          "${var.kb_bucket_arn}/product-docs/*",
          "${var.kb_bucket_arn}/support-policies/*",
        ]
      },
      {
        Sid    = "S3ListKBBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = var.kb_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "product-docs/*",
              "support-policies/*",
            ]
          }
        }
      },
    ]
  })
}

# --- Overpermissive IAM policy (attack scenario) ---
# Only attached when enable_overpermissive_iam = true

resource "aws_iam_role_policy" "overpermissive_data_access" {
  count = var.enable_overpermissive_iam ? 1 : 0

  name = "${local.function_name}-overpermissive-data"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBFullAccess"
        Effect = "Allow"
        Action = "dynamodb:*"
        Resource = "*"
      },
      {
        Sid    = "S3FullAccess"
        Effect = "Allow"
        Action = "s3:*"
        Resource = "*"
      },
    ]
  })
}

# --- Excessive tools write policy ---
# Only needed when excessive tools are enabled AND IAM is NOT overpermissive
# (overpermissive already grants dynamodb:* so this would be redundant)

resource "aws_iam_role_policy" "excessive_tools_write" {
  count = var.enable_excessive_tools && !var.enable_overpermissive_iam ? 1 : 0

  name = "${local.function_name}-excessive-tools-write"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBWriteCustomers"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
        ]
        Resource = var.customers_table_arn
      },
    ]
  })
}

# --- Lambda function ---

resource "aws_lambda_function" "agent_tools" {
  function_name    = local.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      CUSTOMERS_TABLE_NAME = var.customers_table_name
      KB_BUCKET_NAME       = var.kb_bucket_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.agent_tools,
    aws_iam_role_policy.lambda_logging,
  ]

  tags = {
    Name = local.function_name
  }
}
