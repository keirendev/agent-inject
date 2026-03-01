# Scripts

Helper scripts for managing the NovaCrest AI Security Lab.

| Script | Description |
|--------|-------------|
| `setup.sh` | One-command setup: checks prerequisites, inits Terraform, runs apply |
| `teardown.sh` | One-command destroy: tears down all resources to stop costs |
| `swap-scenario.sh` | Switch between misconfiguration scenarios |
| `sync-kb-clean.sh` | Sync clean docs to S3 and trigger KB re-sync |
| `sync-kb-poisoned.sh` | Sync poisoned docs to S3 and trigger KB re-sync |
| `get-my-ip.sh` | Helper to get your current public IP for allowlisting |
