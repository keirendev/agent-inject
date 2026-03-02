# Cost Estimate: NovaCrest AI Security Lab

Region: **ap-southeast-2 (Sydney)** | Account: `983085629416`

Last updated: 2026-03-03

## Daily Cost Breakdown (Infrastructure Running 24/7)

| Resource | Configuration | Hourly Cost | Daily Cost | Notes |
|----------|--------------|-------------|------------|-------|
| **OpenSearch Serverless** | 1 vector search collection, standby replicas DISABLED (0.5 OCU indexing + 0.5 OCU search = 1 OCU) | $0.24 | **$5.76** | Biggest cost driver. Cannot share OCUs with other collection types. |
| **EC2 (Frontend)** | t3.micro, on-demand, Linux | $0.0122 | **$0.29** | Amazon Linux 2023, running Streamlit/Flask UI |
| **Lambda** | 1 function, 256 MB, Python 3.12 | ~$0.00 | **~$0.00** | Free tier: 1M requests + 400K GB-seconds/month. Lab usage is well within free tier. |
| **DynamoDB** | 1 table (PAY_PER_REQUEST), 1 GSI | ~$0.00 | **~$0.00** | Free tier: 25 GB storage + 25 WCU/RCU. Lab has minimal data. |
| **S3** | 3 buckets (KB docs, CloudTrail logs, invocation logs) | ~$0.00 | **~$0.01** | Storage costs negligible at lab scale (<1 GB total). |
| **CloudTrail** | 1 trail, management events only | $0.00 | **$0.00** | First copy of management events is free. S3 storage cost included above. |
| **CloudWatch** | 1 custom dashboard, 2 log groups | ~$0.00 | **~$0.00** | Free tier: 3 dashboards, 5 GB log ingestion, 10 custom metrics. |
| **Bedrock Agent** | Nova Lite v1, ~100 invocations/day | — | **~$0.01** | See model invocation estimate below. |
| **Bedrock Guardrail** | Content filters + denied topics | — | **~$0.01** | $0.15 per 1,000 text units. ~100 invocations = negligible. |
| **Bedrock KB Embeddings** | Titan Embed Text v2 | — | **~$0.00** | Only charged on KB sync (one-time per data source ingestion). |
| **VPC** | 1 VPC, 4 subnets, 1 IGW, 2 gateway endpoints (S3 + DynamoDB) | $0.00 | **$0.00** | Gateway endpoints are free. No NAT gateway deployed. |
| **IAM / Budgets** | Roles, policies, budget alarms | $0.00 | **$0.00** | No charge for IAM or Budgets. |

### **Total Daily Cost: ~$6.07/day**

### **Total Monthly Cost (30 days continuous): ~$182/month**

## Model Invocation Cost Estimate

Assuming ~100 agent invocations per day with an average of 2,000 input tokens and 500 output tokens per invocation:

| Model | Input Price (per 1K tokens) | Output Price (per 1K tokens) | Daily Input Cost | Daily Output Cost | Daily Total |
|-------|----------------------------|-----------------------------|-----------------|--------------------|-------------|
| **Nova Lite** (current) | $0.00006 | $0.00024 | $0.012 | $0.012 | **$0.024** |
| **Nova Micro** (cheapest) | $0.000035 | $0.00014 | $0.007 | $0.007 | **$0.014** |
| **Claude Sonnet 3.5** (validation only) | $0.003 | $0.015 | $0.60 | $0.75 | **$1.35** |

At 100 invocations/day, model costs are negligible with Nova Lite/Micro. Claude Sonnet would add ~$1.35/day but is still within budget if used sparingly.

## Budget Status

| Metric | Value |
|--------|-------|
| Hard daily budget | **$15.00/day** |
| Estimated daily cost (infra running) | **~$6.07/day** |
| Headroom | **~$8.93/day** |
| Under budget? | **Yes** |

The lab is comfortably under the $15/day target, primarily because standby replicas are disabled on the OpenSearch Serverless collection, halving the OCU cost from $11.52/day to $5.76/day.

## Cost When Torn Down

When `terraform destroy` is run, all resources are deleted and the daily cost drops to **$0.00/day**. There are no reserved instances, savings plans, or committed resources.

## Recommendations

1. **Always `terraform destroy` when not actively testing.** OpenSearch Serverless alone costs $5.76/day ($173/month) even when idle. There is no scale-to-zero for OCUs.

2. **Use Nova Micro for routine testing.** It is 40% cheaper than Nova Lite and sufficient for testing prompt injection scenarios. Reserve Nova Lite or Sonnet for final validation runs.

3. **Keep standby replicas disabled.** The current config (`standby_replicas = "DISABLED"`) cuts OpenSearch costs in half. This is acceptable for a lab/dev environment but would not be appropriate for production.

4. **Monitor the $50/month budget alarm.** At ~$6.07/day, continuous 24/7 operation would hit $182/month. If the lab runs for more than ~8 days continuously, the $50 alarm will fire. This is expected behavior and a good reminder to tear down.

5. **Avoid Claude Sonnet for bulk testing.** At $1.35/day for 100 invocations, it is 56x more expensive than Nova Lite. Use it only for final demo recordings or validation.

6. **Consider a tighter budget alarm.** Add a $15/month budget alarm that fires early to catch unexpected charges. See the budget alarm analysis below.

## Budget Alarm Analysis

Current alarms in `terraform/modules/baseline/main.tf`:

| Budget | Threshold | Alert Fires At | Sufficient? |
|--------|-----------|----------------|-------------|
| $50/month | 80% actual | $40 | Good for ~6.5 days of continuous running |
| $50/month | 100% actual | $50 | Good for ~8 days of continuous running |
| $100/month | 80% actual | $80 | Good for ~13 days of continuous running |
| $100/month | 100% actual | $100 | Good for ~16 days of continuous running |
| $100/month | 100% forecasted | $100 projected | Early warning based on spend trend |

**Recommendation:** The existing $50 and $100 alarms are reasonable for this lab. However, consider adding a **$20/month budget** with an 80% threshold ($16 alert) to catch situations where someone forgets to tear down after a single day of testing. This would fire after roughly 2.5 days of continuous operation, providing an early "you left it running" reminder.

## Pricing Sources

- [AWS EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/) -- t3.micro in ap-southeast-2: $0.0122/hr
- [AWS OpenSearch Serverless Pricing](https://aws.amazon.com/opensearch-service/pricing/) -- $0.24/OCU-hour
- [Amazon Nova Pricing](https://aws.amazon.com/nova/pricing/) -- Nova Lite: $0.06/1M input, $0.24/1M output
- [Amazon Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/) -- Guardrails: $0.15/1K text units
- [AWS CloudTrail Pricing](https://aws.amazon.com/cloudtrail/pricing/) -- First management event copy free
- [Amazon CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/) -- 3 dashboards free tier
- [AWS VPC Pricing](https://aws.amazon.com/vpc/pricing/) -- Gateway endpoints free
