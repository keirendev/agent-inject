# Architecture

## Overview

The NovaCrest AI Security Lab deploys a realistic AI-powered customer support system on AWS using Amazon Bedrock Agents. The architecture mirrors what real companies ship today — a tool-calling AI agent with access to a knowledge base and backend systems.

## Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Operator (You)                               │
│                    IP-allowlisted access only                       │
└──────────────┬──────────────────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────┐
│     Frontend (Chat UI)    │
│   Streamlit/Flask on EC2  │
│   - Chat interface        │
│   - Agent trace panel     │
└──────────┬───────────────┘
           │ invoke_agent API
           ▼
┌──────────────────────────────────────────────────────────────────┐
│                      Amazon Bedrock Agent                        │
│  "NovaCrest Support Agent"                                       │
│                                                                  │
│  ┌─────────────┐  ┌──────────────────┐  ┌────────────────────┐  │
│  │ System      │  │ Foundation Model │  │ Guardrails         │  │
│  │ Prompt      │  │ (Nova Lite /     │  │ - Prompt attack    │  │
│  │             │  │  Claude Sonnet)  │  │   detection        │  │
│  └─────────────┘  └──────────────────┘  │ - Content filters  │  │
│                                          │ - PII redaction    │  │
│  ReAct Orchestration Loop:               │ - Denied topics    │  │
│  Thought → Action → Observation → ...    └────────────────────┘  │
└──────┬────────────────────────────┬──────────────────────────────┘
       │                            │
       ▼                            ▼
┌──────────────────┐    ┌──────────────────────────────────────┐
│ Action Group     │    │ Bedrock Knowledge Base               │
│ (Lambda Tools)   │    │                                      │
│                  │    │  S3 Docs → Titan Embeddings →        │
│ - lookup_customer│    │  OpenSearch Serverless (vectors) →   │
│ - check_refund   │    │  Similarity search → Context to LLM │
│ - process_refund │    │                                      │
│ - search_kb      │    └──────────────────────────────────────┘
└──────┬───────────┘
       │
       ▼
┌──────────────────┐    ┌──────────────────┐
│ DynamoDB         │    │ S3 Bucket        │
│ novacrest-       │    │ novacrest-kb-    │
│ customers        │    │ docs             │
│                  │    │ - product-docs/  │
│ ~10 fake records │    │ - support-       │
│                  │    │   policies/      │
│                  │    │ - internal/      │
└──────────────────┘    └──────────────────┘
```

## Data Flow

1. User sends a message via the frontend chat UI
2. Frontend calls the Bedrock Agent `invoke_agent` API
3. The agent's ReAct loop processes the request:
   - Reads the system prompt for instructions
   - Decides if it needs to call a tool or search the knowledge base
   - Executes tool calls via the Lambda Action Group
   - Retrieves relevant documents from the Knowledge Base (RAG)
   - Formulates a response
4. Guardrails check both the input and output for policy violations
5. Response is returned to the user

## Trust Boundaries

```
TRUSTED                          UNTRUSTED
─────────────────────────────────────────────────
System Prompt                    User Input
Tool Schemas (OpenAPI)           Knowledge Base Documents (retrieved)
Lambda Code                      Tool Outputs (data from DynamoDB)
Guardrail Config
```

The critical insight: **Knowledge Base documents and tool outputs enter the LLM's context window alongside the system prompt.** The model cannot distinguish between trusted instructions and untrusted data. This is the fundamental vulnerability that enables indirect prompt injection.

## Terraform Module Map

| Module | Purpose | Key Resources |
|--------|---------|---------------|
| `baseline` | Account security guardrails | CloudTrail, billing alarms, S3 block public access |
| `networking` | Network isolation | VPC, subnets, security groups (operator IP only) |
| `data` | Backend data stores | S3 bucket, DynamoDB table |
| `agent-tools` | Agent capabilities | Lambda function, IAM role, OpenAPI spec |
| `knowledge-base` | RAG pipeline | OpenSearch Serverless, Bedrock KB, data source |
| `agent` | The AI agent | Bedrock Agent, system prompt, KB + AG attachment, UserInput action group |
| `guardrails` | Defensive controls | Bedrock Guardrail configuration |
| `frontend` | User interface | EC2 (t3.micro), Streamlit chat app, IAM instance profile |
| `observability` | Logging, dashboards, security alerting | CloudWatch dashboard (10 widgets), model invocation logging (S3 + CW), 6 metric filters, 8 security alarms, SNS alerts |

## Security Controls (Secure Baseline)

- All network ingress restricted to operator IP via security groups
- IAM roles follow least privilege — scoped to specific resources
- S3 public access blocked at the account level
- CloudTrail enabled for full API audit trail
- Bedrock Guardrails with HIGH sensitivity prompt attack detection
- PII redaction on agent responses
- Refund tool requires user confirmation before execution
- Internal documents excluded from the Knowledge Base data source
