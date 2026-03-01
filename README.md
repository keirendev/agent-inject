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

**Work in Progress** — This project is currently under active development. Check back for updates.

## Quick Start

_Coming soon._

## Architecture

_Coming soon — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)._

## Attack Scenarios

_Coming soon — see [docs/ATTACK_SCENARIOS.md](docs/ATTACK_SCENARIOS.md)._

## Teardown

_Coming soon — run `./scripts/teardown.sh` to destroy all resources._

## References

- [OWASP Top 10 for LLM Applications 2025](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
- [OWASP Top 10 for Agentic Applications](https://genai.owasp.org/)
- [AWS: Securing Bedrock Agents Against Indirect Prompt Injection](https://aws.amazon.com/blogs/machine-learning/securing-amazon-bedrock-agents-a-guide-to-safeguarding-against-indirect-prompt-injections/)

## License

Apache 2.0 — see [LICENSE](LICENSE).
