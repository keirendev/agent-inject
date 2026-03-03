# Terraform Scenarios

Pre-built misconfiguration profiles for the NovaCrest AI Security Lab.

Each `.tfvars` file activates specific combinations of misconfigurations.
Use `../../scripts/swap-scenario.sh <scenario-name>` to switch between them.

| Scenario | Description |
|----------|-------------|
| `secure-baseline.tfvars` | Everything locked down (default) |
| `scenario-rag-poisoning.tfvars` | Internal docs in KB + weak prompt + LOW guardrails — all 3 RAG poisoning attacks succeed |
| `scenario-tool-manipulation.tfvars` | LOW guardrails + no refund confirmation |
| `scenario-data-exfil.tfvars` | Overpermissive IAM + weak prompt + excessive tools + LOW guardrails — all 4 exfil attacks succeed |
| `scenario-prompt-leakage.tfvars` | LOW guardrails + weak system prompt |
| `scenario-full-killchain.tfvars` | All misconfigurations active — complete 9-step kill chain succeeds |
