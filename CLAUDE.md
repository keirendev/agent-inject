# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NovaCrest AI Security Lab — an open-source AI agent security training range built on AWS Bedrock Agents. Deploys a fictional company ("NovaCrest Solutions") customer support agent, then introduces deliberate misconfigurations to demonstrate prompt injection and other agentic AI attacks. The full project plan is in `agentic-ai-security-lab-plan.md`.

**This deploys intentionally vulnerable infrastructure.** Always use a dedicated AWS account.

## Architecture

- **Terraform modules** (`terraform/modules/`): baseline, networking, data, agent-tools, knowledge-base, agent, guardrails, frontend, observability
- **Lambda tools** (`src/lambda/agent_tools/`): Python handlers for the Bedrock Agent Action Group (lookup_customer, check_refund_eligibility, process_refund, search_knowledge_base)
- **Frontend** (`src/frontend/`): Streamlit/Flask chat UI with agent trace debug panel
- **Knowledge base docs** (`knowledge-base-docs/`): `clean/` for legitimate docs, `poisoned/` for injection payloads
- **Scenario system** (`terraform/scenarios/`): `.tfvars` files that toggle misconfigurations via boolean variables; switched with `scripts/swap-scenario.sh`

## Key Commands

```bash
# Deploy secure baseline
./scripts/setup.sh

# Switch to an attack scenario
./scripts/swap-scenario.sh scenario-rag-poisoning

# Sync knowledge base documents
./scripts/sync-kb-clean.sh      # legitimate docs
./scripts/sync-kb-poisoned.sh   # docs with injection payloads

# Tear down everything
./scripts/teardown.sh

# Get operator IP for allowlisting
./scripts/get-my-ip.sh

# Terraform operations (from terraform/ directory)
terraform init
terraform plan -var-file=scenarios/secure-baseline.tfvars
terraform apply -var-file=scenarios/<scenario>.tfvars
terraform destroy
```

## Conventions

- **All infrastructure is Terraform.** No manual AWS console changes. Use variables for anything environment-specific (region, IP, account ID). Never hardcode secrets.
- **Repo-first mindset**: code is written for public sharing. Comments explain "why" not "what". Every directory has a README.
- **Scenario toggle pattern**: misconfigurations are controlled by boolean Terraform variables (e.g., `enable_overpermissive_iam`, `use_weak_system_prompt`). Each scenario `.tfvars` file sets specific combinations.
- **System prompts** live in `prompts/` as separate `.txt` files (secure and weak variants).
- **Cost awareness**: prefer Amazon Nova Lite/Micro for testing, Claude Sonnet only for final validation. OpenSearch Serverless is the biggest cost driver.
- **Hard budget rule**: Total daily AWS cost must not exceed $15/day. OpenSearch Serverless ($5.76/day with standby replicas disabled) is the biggest driver. Always `terraform destroy` when not actively testing. Prefer Nova Micro/Lite over Claude Sonnet for routine testing.
- **Security**: all ingress restricted to operator IP. IAM roles scoped to specific resources. S3 public access blocked at account level. CloudTrail enabled.
- **Documentation**: keep `docs/` and the GitHub Wiki in sync. When implementing a feature or completing a step, update `docs/` files and the wiki Status page. The wiki lives at `git@github.com:keirendev/agent-inject.wiki.git`.



# Git & GitHub Workflow

## Core Principle
Use Git and GitHub as a developer would. The repo is the source of truth for project state, outstanding work, and session continuity.

## Commit Behaviour
- **Pre-commit secret scan**: This repo is public. Before every commit and push, run `gitleaks detect` or `trufflehog filesystem .` to ensure no secrets, credentials, or sensitive information are included. Do not push if any findings are reported.
- Commit after every meaningful unit of work (don't batch unrelated changes)
- Use conventional commit format: `type(scope): description`
  - Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
  - Example: `feat(recon): add subdomain enumeration module`
- Always include a commit body if the change isn't self-explanatory
- Push to remote after committing — don't leave local-only commits

## Session Start Checklist
At the start of every session:
1. `git pull` to get latest state
2. Check open GitHub Issues for outstanding tasks (`gh issue list`)
3. Check open PRs (`gh pr list`)
4. Review recent commits to understand where we left off (`git log --oneline -10`)
5. Resume the highest priority open issue unless instructed otherwise

## Session End Checklist
Before ending a session or when work is paused:
1. Commit and push all in-progress work (use `wip:` prefix if incomplete)
2. If a task is incomplete, update the relevant GitHub Issue with current status and any blockers
3. If new tasks or bugs were discovered during the session, open GitHub Issues for them before closing

## GitHub Issues
- Create an issue for every distinct task, bug, or finding before starting work on it
- Use labels to categorise: `bug`, `enhancement`, `research`, `blocked`, `wip`
- Assign issues to milestones if working toward a specific deliverable
- Close issues with commit references: `Closes #12` in the commit message
- If something is discovered mid-task that's out of scope, open a new issue rather than scope-creeping the current one

## Branches
- `main` is always stable/deployable
- Create feature branches for non-trivial work: `git checkout -b feature/issue-12-xss-scanner`
- Branch naming: `type/issue-number-short-description`
- Merge via PR, not direct push to main (unless it's a minor fix)

## Pull Requests
- Open a PR when a feature branch is ready for review or merging
- PR description should reference the issue it closes and summarise what changed
- Keep PRs focused — one concern per PR

## Context Recovery
If unsure what we were working on, in order:
1. `gh issue list --state open`
2. `git log --oneline -20`
3. `git stash list`
4. Check any `wip:` commits on current branch