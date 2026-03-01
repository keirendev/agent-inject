# Terraform Scenarios

Pre-built misconfiguration profiles for the NovaCrest AI Security Lab.

Each `.tfvars` file activates specific combinations of misconfigurations.
Use `../../scripts/swap-scenario.sh <scenario-name>` to switch between them.

| Scenario | Description |
|----------|-------------|
| `secure-baseline.tfvars` | Everything locked down (default) |
| `scenario-rag-poisoning.tfvars` | Internal docs in KB + guardrail lowered |
| `scenario-tool-manipulation.tfvars` | Guardrail lowered + no refund confirmation |
| `scenario-data-exfil.tfvars` | Over-permissive IAM + weak system prompt |
| `scenario-prompt-leakage.tfvars` | Guardrail lowered + weak system prompt |
| `scenario-full-killchain.tfvars` | All misconfigurations active |
