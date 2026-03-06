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
| `product-faq-injected.md` | Hidden instruction in a product FAQ + fake system prompt disclosure |
| `refund-policy-injected.md` | Triggers unauthorized refund processing |
| `pricing-tiers-injected.md` | Replaces clean pricing with deceptive prices ($12/$15/$25 vs $99.99/$79.99/$499.99) |
| `onboarding-guide-injected.md` | Planted credentials, API keys, CI/CD passwords, and database connection strings |
