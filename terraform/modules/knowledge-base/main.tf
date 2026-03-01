# -----------------------------------------------------------------------------
# Knowledge Base module - OpenSearch Serverless + Bedrock Knowledge Base
#
# Creates:
#   - OpenSearch Serverless collection (vector search, standby disabled)
#   - Encryption, network, and data access security policies
#   - Vector index for storing document embeddings
#   - Bedrock Knowledge Base connected to the collection
#   - Data source(s) pointing to S3 KB docs bucket
#   - IAM role granting Bedrock access to S3 + OpenSearch + embeddings
#
# The kb_include_internal_docs toggle controls which S3 prefixes are indexed:
#   false (secure): only product-docs/ and support-policies/
#   true  (vulnerable): entire bucket including internal/
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  collection_name = "${var.project_name}-${var.environment}-kb"
  kb_name         = "${var.project_name}-${var.environment}-knowledge-base"

  # Vector index configuration for Titan Embed Text v2 (1024 dimensions)
  vector_index_name = "bedrock-kb-index"
  vector_field      = "bedrock-knowledge-base-default-vector"
  text_field        = "AMAZON_BEDROCK_TEXT_CHUNK"
  metadata_field    = "AMAZON_BEDROCK_METADATA"
  vector_dimension  = 1024

  # S3 prefixes for secure mode (one data source per prefix)
  secure_prefixes = ["product-docs/", "support-policies/"]
}

# =============================================================================
# OpenSearch Serverless
# =============================================================================

# Encryption at rest (required before collection creation)
resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${local.collection_name}-enc"
  type = "encryption"

  policy = jsonencode({
    Rules = [{
      Resource     = ["collection/${local.collection_name}"]
      ResourceType = "collection"
    }]
    AWSOwnedKey = true
  })
}

# Network access - public for lab simplicity
resource "aws_opensearchserverless_security_policy" "network" {
  name = "${local.collection_name}-net"
  type = "network"

  policy = jsonencode([{
    Description = "Public access for lab collection"
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${local.collection_name}"]
      }
    ]
    AllowFromPublic = true
  }])
}

# Data access - grants Terraform user and Bedrock role access to indices
resource "aws_opensearchserverless_access_policy" "data" {
  name = "${local.collection_name}-access"
  type = "data"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "index"
        Resource     = ["index/${local.collection_name}/*"]
        Permission   = ["aoss:*"]
      },
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
        Permission   = ["aoss:*"]
      }
    ]
    Principal = [
      data.aws_caller_identity.current.arn,
      aws_iam_role.kb_role.arn,
    ]
  }])
}

# The collection itself - VECTORSEARCH type, standby disabled to minimize cost
resource "aws_opensearchserverless_collection" "kb" {
  name             = local.collection_name
  type             = "VECTORSEARCH"
  standby_replicas = "DISABLED"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.data,
  ]

  tags = {
    Name = local.collection_name
  }
}

# Vector index inside the collection - created via AWS CLI (awscurl)
# Using null_resource avoids the opensearch provider's chicken-and-egg problem
# where the collection endpoint isn't known until after the first apply.
resource "null_resource" "kb_vector_index" {
  provisioner "local-exec" {
    command = <<-EOT
      python3 -c "
import boto3
import json
import time
import sys
import requests
from requests_aws4auth import AWS4Auth

region = '${var.aws_region}'
collection_id = '${aws_opensearchserverless_collection.kb.id}'
endpoint = '${aws_opensearchserverless_collection.kb.collection_endpoint}'
index_name = '${local.vector_index_name}'

# Wait for collection to be ACTIVE
print('Waiting for OpenSearch collection to become ACTIVE...')
client = boto3.client('opensearchserverless', region_name=region)
for attempt in range(60):
    resp = client.batch_get_collection(ids=[collection_id])
    status = resp['collectionDetails'][0]['status']
    if status == 'ACTIVE':
        print('Collection is ACTIVE')
        break
    print(f'Status: {status} (attempt {attempt+1}/60)')
    time.sleep(10)
else:
    print('ERROR: Collection did not become ACTIVE in time')
    sys.exit(1)

# Wait for data access policy to propagate
print('Waiting 30s for data access policy to propagate...')
time.sleep(30)

# Create vector index with retries
credentials = boto3.Session().get_credentials().get_frozen_credentials()
auth = AWS4Auth(credentials.access_key, credentials.secret_key, region, 'aoss', session_token=credentials.token)

body = {
    'settings': {
        'index': {
            'number_of_shards': 2,
            'number_of_replicas': 0,
            'knn': True,
            'knn.algo_param.ef_search': 512
        }
    },
    'mappings': {
        'properties': {
            '${local.vector_field}': {
                'type': 'knn_vector',
                'dimension': ${local.vector_dimension},
                'method': {
                    'engine': 'faiss',
                    'name': 'hnsw',
                    'parameters': {
                        'm': 16,
                        'ef_construction': 512
                    }
                }
            },
            '${local.text_field}': {
                'type': 'text',
                'index': True
            },
            '${local.metadata_field}': {
                'type': 'text',
                'index': False
            }
        }
    }
}

url = f'{endpoint}/{index_name}'
for attempt in range(6):
    resp = requests.put(url, auth=auth, json=body, headers={'Content-Type': 'application/json'})
    if resp.status_code == 200:
        print(f'Index created: {resp.text}')
        sys.exit(0)
    elif 'resource_already_exists_exception' in resp.text:
        print('Index already exists - OK')
        sys.exit(0)
    elif resp.status_code == 403 and attempt < 5:
        print(f'403 Forbidden (attempt {attempt+1}/6) - waiting 30s...')
        time.sleep(30)
    else:
        print(f'Error {resp.status_code}: {resp.text}')
        sys.exit(1)

print('ERROR: Failed to create index after all retries')
sys.exit(1)
"
    EOT

    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    collection_id = aws_opensearchserverless_collection.kb.id
    index_name    = local.vector_index_name
  }

  depends_on = [aws_opensearchserverless_collection.kb]
}

# =============================================================================
# IAM Role for Bedrock Knowledge Base
# =============================================================================

resource "aws_iam_role" "kb_role" {
  name = "${local.kb_name}-role"

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
    Name = "${local.kb_name}-role"
  }
}

resource "aws_iam_role_policy" "kb_permissions" {
  name = "${local.kb_name}-permissions"
  role = aws_iam_role.kb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${data.aws_region.current.id}::foundation-model/amazon.titan-embed-text-v2:0"
      },
      {
        Sid    = "S3ReadKBDocs"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.kb_bucket_arn,
          "${var.kb_bucket_arn}/*",
        ]
      },
      {
        Sid    = "OpenSearchAccess"
        Effect = "Allow"
        Action = ["aoss:APIAccessAll"]
        Resource = aws_opensearchserverless_collection.kb.arn
      },
    ]
  })
}

# =============================================================================
# Bedrock Knowledge Base
# =============================================================================

data "aws_bedrock_foundation_model" "embedding" {
  model_id = "amazon.titan-embed-text-v2:0"
}

resource "aws_bedrockagent_knowledge_base" "kb" {
  name     = local.kb_name
  role_arn = aws_iam_role.kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = data.aws_bedrock_foundation_model.embedding.model_arn
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = local.vector_index_name
      field_mapping {
        vector_field   = local.vector_field
        text_field     = local.text_field
        metadata_field = local.metadata_field
      }
    }
  }

  depends_on = [
    null_resource.kb_vector_index,
    aws_iam_role_policy.kb_permissions,
  ]

  tags = {
    Name = local.kb_name
  }
}

# =============================================================================
# Data Sources - conditional on kb_include_internal_docs toggle
# =============================================================================

# Secure mode: 2 data sources with prefix filters (product-docs/, support-policies/)
resource "aws_bedrockagent_data_source" "secure" {
  count = var.kb_include_internal_docs ? 0 : length(local.secure_prefixes)

  knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id
  name              = "${var.project_name}-${var.environment}-${replace(local.secure_prefixes[count.index], "/", "")}"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = var.kb_bucket_arn
      inclusion_prefixes = [local.secure_prefixes[count.index]]
    }
  }
}

# Vulnerable mode: 1 data source for the entire bucket (includes internal/)
resource "aws_bedrockagent_data_source" "vulnerable" {
  count = var.kb_include_internal_docs ? 1 : 0

  knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id
  name              = "${var.project_name}-${var.environment}-all-docs"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = var.kb_bucket_arn
    }
  }
}
