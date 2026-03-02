# NovaCrest AI Security Lab

> **An open-source AI agent security training range built on AWS Bedrock Agents.**

---

> **WARNING**: This project deploys **intentionally vulnerable** infrastructure into your AWS account.
> Use a **dedicated AWS account** — never your production account. Understand the costs involved
> (see [COST_ESTIMATE.md](COST_ESTIMATE.md)). **Tear down the environment when you're done** to avoid
> ongoing charges. You are responsible for all AWS costs incurred.

---

## What Is This?

This repo builds a realistic mock company environment ("NovaCrest Solutions") that uses AI agents
(Amazon Bedrock Agents) for customer support. The environment is first deployed in a secure,
production-like state, then deliberately misconfigured to simulate common real-world mistakes.
Each misconfiguration is exploited to demonstrate realistic attack chains — primarily focused on
prompt injection through tool-calling agents.

Use it to learn about agentic AI security, practice offensive techniques in a safe lab, or
train your team on the risks of deploying AI agents without proper guardrails.

## Status

**Phase 1 (Secure Baseline) — Complete**

| Step | Module | Status |
|------|--------|--------|
| 0 | Repo scaffold & tooling | Done |
| 1 | Baseline (CloudTrail, billing, S3 block) | Done |
| 2 | Networking (VPC, subnets, SGs) | Done |
| 3 | Data (S3, DynamoDB, fake customers) | Done |
| 4 | Agent Tools (Lambda + OpenAPI spec) | Done |
| 5 | Knowledge Base (OpenSearch Serverless + Bedrock KB) | Done |
| 6 | Agent (Bedrock Agent + system prompt) | Done |
| 7 | Guardrails (content filters, PII redaction, prompt attack detection) | Done |
| 8 | Frontend (Streamlit chat UI on EC2) | Done |
| 9 | Observability (CloudWatch) | Planned |

**Phase 2** (Attack Scenarios), **Phase 3** (Exploitation), **Phase 4** (Remediation) — Not started.

## Quick Start

### Prerequisites

- AWS CLI v2, Terraform v1.5+, Python 3.11+
- A dedicated AWS account with Bedrock model access enabled (see [docs/SETUP.md](docs/SETUP.md))

### Deploy

```bash
git clone git@github.com:keirendev/agent-inject.git
cd agent-inject/terraform

terraform init
terraform apply \
  -var-file=scenarios/secure-baseline.tfvars \
  -var="operator_ip=$(curl -s https://checkip.amazonaws.com)" \
  -var="alert_email=your@email.com"
```

After apply completes, the `frontend_url` output gives you the Streamlit chat UI. Wait 2-3 minutes for the EC2 setup script to finish.

### Tear Down

```bash
cd terraform
terraform destroy \
  -var-file=scenarios/secure-baseline.tfvars \
  -var="operator_ip=$(curl -s https://checkip.amazonaws.com)" \
  -var="alert_email=your@email.com"
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full diagram and component breakdown.

```
Operator → Frontend (Streamlit/EC2) → Bedrock Agent → Lambda Tools + Knowledge Base
                                          ↓
                                     Guardrails (content filters, PII redaction)
```

**9 Terraform modules**: baseline, networking, data, agent-tools, knowledge-base, agent, guardrails, frontend, observability.

## Attack Scenarios

Scenario `.tfvars` files toggle deliberate misconfigurations:

- **RAG Poisoning**: Inject malicious instructions into knowledge base documents
- **Weak System Prompt**: Remove security boundaries from the agent's instructions
- **Overpermissive IAM**: Give the agent excessive tool access
- **Guardrail Bypass**: Lower or disable content filtering
- **Tool Manipulation**: Remove refund confirmation, enable parameter swapping
- **Full Kill Chain**: All misconfigurations active — 9-step attack chain

## Automated Test Harness

A Python CLI test runner sends attack payloads to the deployed agent, captures full traces, validates outcomes against assertions, and generates markdown reports.

### Quick Start

```bash
# Install test dependencies
pip install -r tests/requirements.txt

# Validate all test definitions (no agent needed)
./scripts/run-tests.sh --all --dry-run

# Run tests for a specific scenario (agent must be deployed)
./scripts/run-tests.sh secure-baseline
./scripts/run-tests.sh scenario-rag-poisoning --verbose

# Run all scenarios
./scripts/run-tests.sh --all

# Review results
cat tests/results/secure-baseline/*/summary.md
```

### Typical Workflow

```bash
# 1. Deploy a scenario
./scripts/swap-scenario.sh scenario-rag-poisoning
./scripts/sync-kb-poisoned.sh

# 2. Run matching tests
./scripts/run-tests.sh scenario-rag-poisoning

# 3. Review results
cat tests/results/scenario-rag-poisoning/*/summary.md

# 4. Switch to secure baseline and verify attacks are blocked
./scripts/swap-scenario.sh secure-baseline
./scripts/sync-kb-clean.sh
./scripts/run-tests.sh secure-baseline
```

Test definitions live in `tests/definitions/` as YAML files. Reports are generated in `tests/results/`.

## Cost

Primary cost driver: **OpenSearch Serverless** (~$11.52/day for 2 OCU minimum). See [COST_ESTIMATE.md](COST_ESTIMATE.md). Always destroy when not actively testing.

## References

- [OWASP Top 10 for LLM Applications 2025](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
- [OWASP Top 10 for Agentic Applications](https://genai.owasp.org/)
- [AWS: Securing Bedrock Agents Against Indirect Prompt Injection](https://aws.amazon.com/blogs/machine-learning/securing-amazon-bedrock-agents-a-guide-to-safeguarding-against-indirect-prompt-injections/)

## License

Apache 2.0 — see [LICENSE](LICENSE).
