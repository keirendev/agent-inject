# Cost Estimate

_Detailed AWS cost breakdown coming soon._

Expected total: ~$20-50 for the full project.

Key cost drivers:
- Bedrock model invocations (Nova Lite/Micro for testing, Claude Sonnet for validation)
- OpenSearch Serverless (minimum 2 OCUs while running)
- Lambda invocations (minimal, likely free tier)
- S3 storage (minimal, likely free tier)
- DynamoDB (minimal, likely free tier)

**Set up billing alarms at $50 and $100 before deploying.**
