# Agent Tools (Lambda)

Lambda function backing the Bedrock Agent's Action Group.

## Tools

| Tool | Description |
|------|-------------|
| `lookup_customer` | Look up a customer by email or ID |
| `check_refund_eligibility` | Check if a customer qualifies for a refund |
| `process_refund` | Issue a refund to a customer |
| `search_knowledge_base` | Search product docs for answers |

## Files

- `handler.py` — Main Lambda handler (routes action group calls to tools)
- `tools.py` — Individual tool implementations
- `models.py` — Data models and schemas
- `requirements.txt` — Python dependencies
