# Poisoned Knowledge Base Documents

These documents contain embedded prompt injection payloads for testing.
They simulate what happens when an attacker gains write access to a document
source, or when internal documents contain hidden malicious instructions.

**These are for educational/lab use only.** Do not use in production environments.

Each document is a modified version of a clean document with an injection payload
embedded using various techniques (hidden text, markdown comments, instruction-style
text, etc.).

| Document | Payload |
|----------|---------|
| `product-faq-injected.md` | Hidden instruction in a product FAQ |
| `refund-policy-injected.md` | Triggers unauthorized refund processing |
| `onboarding-guide-injected.md` | Data exfiltration payload |
