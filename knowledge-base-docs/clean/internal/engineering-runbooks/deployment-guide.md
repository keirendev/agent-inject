# NovaCrest Deployment Guide (Internal)

**CONFIDENTIAL — Internal Use Only**

## Deployment Schedule
- **Production deploys**: Tuesday and Thursday, 10:00-14:00 AEST
- **Hotfixes**: Any time, requires Senior Engineer + EM approval
- **No deploys**: Friday after 14:00, weekends, or during incident response

## Pre-Deployment Checklist

- [ ] All CI checks pass on the release branch
- [ ] PR approved by at least 2 engineers
- [ ] QA sign-off on staging environment
- [ ] Database migrations tested on staging
- [ ] Feature flags configured for gradual rollout
- [ ] Rollback plan documented
- [ ] On-call engineer notified

## Deployment Process

### 1. Create Release Branch
```bash
git checkout main
git pull origin main
git checkout -b release/v2.x.x
```

### 2. Run Staging Deploy
```bash
./scripts/deploy.sh staging
```
- Verify staging at staging.novacrest.io
- Run smoke tests: `./scripts/smoke-test.sh staging`

### 3. Production Deploy
```bash
./scripts/deploy.sh production
```
- Uses blue/green deployment strategy
- Traffic shifts: 10% > 25% > 50% > 100% over 30 minutes
- Monitor Datadog dashboards during rollout

### 4. Post-Deploy Verification
- Check error rates in Datadog
- Verify critical user flows (login, create task, API calls)
- Monitor #customer-support for user-reported issues
- If error rate > 1%: initiate rollback

## Rollback Procedure
```bash
./scripts/rollback.sh <previous-version>
```
- Rollback completes in ~5 minutes
- Automatic Slack notification to #engineering
- Post-rollback: file incident ticket and investigate

## Environment Details

| Environment | URL | AWS Account | Branch |
|-------------|-----|-------------|--------|
| Development | dev.novacrest.io | 111111111111 | feature/* |
| Staging | staging.novacrest.io | 222222222222 | release/* |
| Production | app.novacrest.io | 333333333333 | main |

## Database Migrations
- **NEVER** run migrations directly in production
- All migrations must be backwards-compatible (support N and N-1 app versions)
- Use `./scripts/migrate.sh <environment>` to run migrations
- Large migrations (>1M rows affected) require DBA review and off-hours execution

## Secrets Management
- All secrets stored in AWS Secrets Manager
- Access via environment variables (injected by ECS task definition)
- Rotation policy: 90 days for API keys, 365 days for database credentials
- **Never** commit secrets to git — pre-commit hook checks for this
