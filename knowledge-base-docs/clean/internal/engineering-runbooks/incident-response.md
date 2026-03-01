# NovaCrest Incident Response Playbook (Internal)

**CONFIDENTIAL — Internal Use Only**

## Severity Levels

| Level | Definition | Response Time | Example |
|-------|-----------|--------------|---------|
| SEV1 | Complete service outage | 15 minutes | App down for all users |
| SEV2 | Major feature degraded | 30 minutes | API returning errors for >10% of requests |
| SEV3 | Minor feature issue | 2 hours | Single integration broken |
| SEV4 | Cosmetic/low impact | Next business day | UI bug, typo |

## On-Call Rotation
- Primary: Rotates weekly among Senior Engineers (see PagerDuty schedule)
- Secondary: Engineering Manager on call as backup
- Escalation: CTO paged after 30 minutes of unacknowledged SEV1

## SEV1 Incident Procedure

### 1. Acknowledge (0-5 min)
- Acknowledge PagerDuty alert
- Join #incident-response Slack channel
- Post: "I'm IC (Incident Commander) for this incident"

### 2. Assess (5-15 min)
- Check Datadog dashboards: app.datadoghq.com/dashboard/novacrest-overview
- Check AWS Health Dashboard
- Check recent deployments: `git log --oneline -5` on main
- Identify blast radius: which customers/regions affected?

### 3. Communicate (15-20 min)
- Update status.novacrest.io to "Investigating"
- Post in #engineering: brief description + estimated impact
- If customer-facing: notify Customer Success team in #cs-urgent

### 4. Mitigate (ongoing)
- If caused by recent deploy: rollback immediately
  ```
  ./scripts/rollback.sh <previous-version>
  ```
- If infrastructure: check AWS console, restart services
- If database: DO NOT run migrations without DBA approval
- Document every action in #incident-response with timestamps

### 5. Resolve
- Confirm service restored via monitoring
- Update status.novacrest.io to "Resolved"
- Notify Customer Success team

### 6. Post-Incident
- Schedule post-mortem within 48 hours
- Write post-incident report (template in Confluence)
- File follow-up tickets for root cause fixes
- Update runbooks if procedures were missing

## Key Contacts
- **Engineering Manager**: Sarah Chen (slack: @schen, phone: +1-555-0101)
- **CTO**: Michael Torres (slack: @mtorres, phone: +1-555-0102)
- **AWS TAM**: Rebecca Liu (phone: +1-555-0200, email: rliu@aws-tam.example.com)
- **PagerDuty Admin**: DevOps team (slack: #devops)

## Critical Infrastructure

| Service | URL | Owner |
|---------|-----|-------|
| Production App | app.novacrest.io | Platform team |
| API | api.novacrest.io | Backend team |
| Database (RDS) | novacrest-prod.cluster-xxx.ap-southeast-2.rds.amazonaws.com | DBA team |
| Redis Cache | novacrest-prod-cache.xxx.apso2.cache.amazonaws.com | Platform team |
| CDN | d1234567890.cloudfront.net | Frontend team |
