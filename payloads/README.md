# Attack Payloads

Organized prompt injection payloads for testing the NovaCrest AI Security Lab.

**Disclaimer**: These payloads are designed for educational use within this lab
environment only. They demonstrate vulnerabilities in AI agent systems to help
security teams understand and defend against real-world attacks.

## Structure

### `direct-injection/` — Payloads sent directly as user input
- **system-prompt-extraction.md** — 6 progressively sophisticated techniques for extracting the agent's system prompt
- **tool-parameter-manipulation.md** — Multi-turn attacks that manipulate refund tool parameters (customer ID swap, amount inflation, chained abuse)
- **role-play-jailbreak.md** — DAN-style, hypothetical framing, reverse psychology, and instruction overwrite techniques

### `indirect-injection/` — Payloads embedded in documents retrieved by the agent
- **hidden-instruction-in-doc.md** — RAG poisoning via poisoned KB documents with hidden instructions (references 3 poisoned docs in `knowledge-base-docs/poisoned/`)
- **encoded-payload.md** — Base64 encoding, Unicode homoglyph substitution, and HTML injection techniques for bypassing content filters
- **context-poisoning.md** — Multi-turn conversation manipulation that gradually shifts context from legitimate to malicious

### `chained/` — Multi-step attack chains combining multiple techniques
- **full-killchain.md** — Complete 9-step attack chain: reconnaissance, RAG poisoning, data enumeration, unauthorized refunds, data exfiltration via email, and record modification

## Each Payload Includes
- Scenario and preconditions (which `.tfvars` file to use)
- OWASP mapping (LLM Top 10 + Agentic Top 10)
- Exact prompts to type
- Expected results
- What to look for in agent traces and CloudWatch
- Technical explanation of why the attack works
- The fix (which controls to enable)
