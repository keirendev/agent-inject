# Scenario: Full Kill Chain
#
# ALL misconfigurations active. This is the showpiece scenario demonstrating
# how small, individually-defensible mistakes compound into a full compromise.
#
# Misconfigurations active:
#   - enable_overpermissive_iam = true    (Lambda has wildcard DynamoDB/S3 access)
#   - guardrail_sensitivity = "NONE"      (all guardrails disabled)
#   - kb_include_internal_docs = true     (internal docs indexed, RAG poisoning)
#   - enable_refund_confirmation = false  (no confirmation before refund)
#   - use_weak_system_prompt = true       (no security boundaries)
#   - enable_excessive_tools = true       (send_email, update_customer, internal query)
#
# Attack chain:
#   1. Extract system prompt (recon)
#   2. Retrieve poisoned KB doc (injection)
#   3. Access internal_notes (data breach)
#   4. Process unauthorized refund (financial impact)
#   5. Exfiltrate data via send_email (persistent access)
#   6. Modify customer records to cover tracks
#
# OWASP: Demonstrates nearly every risk from both LLM and Agentic Top 10 lists.
#
# Setup:
#   1. ./scripts/swap-scenario.sh scenario-full-killchain
#   2. ./scripts/sync-kb-poisoned.sh

enable_overpermissive_iam  = true
guardrail_sensitivity      = "NONE"
kb_include_internal_docs   = true
enable_refund_confirmation = false
use_weak_system_prompt     = true
enable_excessive_tools     = true
