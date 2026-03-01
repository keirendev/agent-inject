# -----------------------------------------------------------------------------
# S3 Bucket — Knowledge Base documents
# Stores the markdown files that the Bedrock Knowledge Base will index.
# In secure config, only product-docs/ and support-policies/ are synced
# to the KB. The internal/ folder exists here but is excluded.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "kb_docs" {
  bucket        = "${var.project_name}-${var.environment}-kb-docs"
  force_destroy = true # Lab environment — allow easy teardown
}

resource "aws_s3_bucket_versioning" "kb_docs" {
  bucket = aws_s3_bucket.kb_docs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# DynamoDB Table — Customer records
# The agent's tools query this table to look up customers, check refund
# eligibility, and process refunds. The internal_notes field contains
# sensitive data that the agent should NOT expose in secure config.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "customers" {
  name         = "${var.project_name}-${var.environment}-customers"
  billing_mode = "PAY_PER_REQUEST" # No cost when idle — only pay per read/write

  hash_key = "customer_id"

  attribute {
    name = "customer_id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  # GSI for looking up customers by email address
  global_secondary_index {
    name            = "email-index"
    hash_key        = "email"
    projection_type = "ALL"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-customers"
  }
}
