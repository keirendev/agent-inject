# NovaCrest Support Escalation Procedures

## Tier 1: AI Support Agent
- **Handles**: Account questions, product how-to, password resets, basic billing inquiries
- **Tools available**: Customer lookup, knowledge base search, refund eligibility check
- **Escalation trigger**: Customer requests human agent, issue is outside scope, or sensitive account flag detected

## Tier 2: Human Support Agent
- **Handles**: Complex billing issues, technical troubleshooting, feature requests, bug reports
- **Access**: Full customer account details, internal documentation, ticketing system
- **Escalation trigger**: Issue unresolved after 2 interactions, customer dissatisfaction, or security-related concern

## Tier 3: Senior Support / Engineering
- **Handles**: Bug investigation, data recovery, API issues, integration troubleshooting
- **Access**: Application logs, error tracking, staging environment
- **Escalation trigger**: Confirmed bug, data integrity issue, or outage-related support

## Tier 4: Management
- **Handles**: Escalated complaints, refunds over $500, legal concerns, SLA breach claims
- **Access**: All systems plus financial approvals

## Escalation Path

```
Customer
  └─> Tier 1: AI Agent (automated)
        └─> Tier 2: Human Support (email/chat)
              └─> Tier 3: Senior Support / Engineering
                    └─> Tier 4: Management
```

## When to Escalate

| Situation | Escalate To |
|-----------|-------------|
| Customer asks for human agent | Tier 2 |
| Refund request over $500 | Tier 4 |
| Account security concern | Tier 3 |
| Threatened legal action | Tier 4 |
| Bug or data loss reported | Tier 3 |
| SLA breach claim | Tier 4 |
| Customer has been waiting >24 hours | Tier 2 (priority) |

## Response Time Targets by Escalation

| Tier | First Response | Resolution Target |
|------|---------------|-------------------|
| Tier 1 (AI) | Immediate | Immediate |
| Tier 2 | Per SLA (see SLA terms) | 24-48 hours |
| Tier 3 | 2 hours | 3-5 business days |
| Tier 4 | 1 hour | Case dependent |
