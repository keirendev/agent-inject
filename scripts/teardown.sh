#!/usr/bin/env bash
# teardown.sh — Safely destroy all NovaCrest AI Security Lab infrastructure
#
# Handles the Bedrock Agent action group deletion gotcha: action groups must
# be disabled before terraform destroy, or it fails with 409 ConflictException.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [[ ! -t 1 ]]; then RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''; fi

info()    { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

# ---------------------------------------------------------------------------
# Phase 1: Safety checks
# ---------------------------------------------------------------------------
for cmd in terraform aws jq; do
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd is required but not installed."
    exit 1
  fi
done

# Check Terraform state has resources
if ! terraform -chdir="$TF_DIR" state list &>/dev/null; then
  info "No Terraform state found. Nothing to destroy."
  exit 0
fi

RESOURCE_COUNT=$(terraform -chdir="$TF_DIR" state list 2>/dev/null | wc -l | tr -d ' ')
if [[ "$RESOURCE_COUNT" -eq 0 ]]; then
  info "No resources in Terraform state. Nothing to destroy."
  exit 0
fi

# ---------------------------------------------------------------------------
# Phase 2: Confirmation
# ---------------------------------------------------------------------------
echo ""
printf "${RED}${BOLD}==============================================${NC}\n"
printf "${RED}${BOLD}  DESTROY ALL NOVACREST LAB RESOURCES${NC}\n"
printf "${RED}${BOLD}==============================================${NC}\n"
echo ""
echo "  This will permanently destroy ALL infrastructure including:"
echo "    - Bedrock Agent and Knowledge Base"
echo "    - OpenSearch Serverless collection"
echo "    - Lambda functions and DynamoDB tables"
echo "    - VPC, security groups, and EC2 instance"
echo "    - CloudTrail, CloudWatch dashboard, and logging"
echo "    - S3 buckets and all stored data"
echo ""
echo "  Resources in Terraform state: $RESOURCE_COUNT"
echo ""

if [[ -t 0 ]]; then
  read -rp "  Type 'destroy' to confirm: " CONFIRM
  if [[ "$CONFIRM" != "destroy" ]]; then
    info "Aborted."
    exit 0
  fi
else
  warn "Non-interactive mode — proceeding with destroy."
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 3: Disable agent action groups (prevents 409 ConflictException)
# ---------------------------------------------------------------------------
info "Checking for Bedrock Agent action groups to disable..."

AGENT_ID=$(terraform -chdir="$TF_DIR" output -raw agent_id 2>/dev/null || echo "")

# Fallback: if outputs are gone (partial destroy), extract agent ID from state
if [[ -z "$AGENT_ID" ]]; then
  AGENT_ID=$(terraform -chdir="$TF_DIR" state show module.agent.aws_bedrockagent_agent.support_agent 2>/dev/null \
    | grep '^\s*agent_id\s*=' | head -1 | sed 's/.*=\s*"\(.*\)"/\1/' || echo "")
fi

REGION=$(terraform -chdir="$TF_DIR" output -raw aws_region 2>/dev/null \
  || aws configure get region 2>/dev/null \
  || echo "ap-southeast-2")

if [[ -z "$AGENT_ID" ]]; then
  warn "Could not determine agent_id from Terraform outputs."
  warn "If destroy fails with 409 ConflictException, disable action groups manually."
else
  info "Agent ID: $AGENT_ID (region: $REGION)"

  AG_JSON=$(aws bedrock-agent list-agent-action-groups \
    --agent-id "$AGENT_ID" \
    --agent-version DRAFT \
    --region "$REGION" \
    --output json 2>/dev/null || echo "")

  if [[ -n "$AG_JSON" ]] && echo "$AG_JSON" | jq -e '.actionGroupSummaries[]' &>/dev/null; then
    echo "$AG_JSON" | jq -r '.actionGroupSummaries[] | .actionGroupId' | while read -r AG_ID; do
      # Get full details (name, executor, schema are required for the update call)
      AG_DETAILS=$(aws bedrock-agent get-agent-action-group \
        --agent-id "$AGENT_ID" \
        --agent-version DRAFT \
        --action-group-id "$AG_ID" \
        --region "$REGION" \
        --output json 2>/dev/null || echo "")

      if [[ -z "$AG_DETAILS" ]]; then
        warn "Could not get details for action group $AG_ID — skipping."
        continue
      fi

      AG_NAME=$(echo "$AG_DETAILS" | jq -r '.agentActionGroup.actionGroupName')
      AG_STATE=$(echo "$AG_DETAILS" | jq -r '.agentActionGroup.actionGroupState')

      if [[ "$AG_STATE" != "ENABLED" ]]; then
        info "Action group '$AG_NAME' already $AG_STATE — skipping."
        continue
      fi

      info "Disabling action group: $AG_NAME ($AG_ID)"

      # Extract executor, schema, and parent signature for the update call
      LAMBDA_ARN=$(echo "$AG_DETAILS" | jq -r '.agentActionGroup.actionGroupExecutor.lambda // empty')
      API_SCHEMA=$(echo "$AG_DETAILS" | jq -r '.agentActionGroup.apiSchema.payload // empty')
      PARENT_SIG=$(echo "$AG_DETAILS" | jq -r '.agentActionGroup.parentActionGroupSignature // .agentActionGroup.parentActionSignature // empty')

      # Build update args
      UPDATE_ARGS=(
        --agent-id "$AGENT_ID"
        --agent-version DRAFT
        --action-group-id "$AG_ID"
        --action-group-name "$AG_NAME"
        --action-group-state DISABLED
        --region "$REGION"
      )

      if [[ -n "$PARENT_SIG" ]]; then
        # Built-in action groups (e.g. AMAZON.UserInput) use parent signature, not lambda/schema
        UPDATE_ARGS+=(--parent-action-group-signature "$PARENT_SIG")
      else
        if [[ -n "$LAMBDA_ARN" ]]; then
          UPDATE_ARGS+=(--action-group-executor "{\"lambda\":\"$LAMBDA_ARN\"}")
        fi

        if [[ -n "$API_SCHEMA" ]]; then
          ESCAPED_SCHEMA=$(echo "$API_SCHEMA" | jq -Rs .)
          UPDATE_ARGS+=(--api-schema "{\"payload\":$ESCAPED_SCHEMA}")
        fi
      fi

      if DISABLE_ERR=$(aws bedrock-agent update-agent-action-group "${UPDATE_ARGS[@]}" --output text 2>&1); then
        success "Disabled action group: $AG_NAME"
      else
        warn "Failed to disable action group: $AG_NAME"
        warn "Error: $DISABLE_ERR"
        warn "Destroy may fail with 409 — if so, disable it manually and retry."
      fi
    done
  else
    info "No action groups found (agent may already be partially deleted)."
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 4: Resolve required variables for destroy
# ---------------------------------------------------------------------------
DESTROY_ARGS=(-var-file=scenarios/secure-baseline.tfvars -auto-approve)

if [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
  warn "terraform.tfvars not found — providing required variables for destroy."
  OPERATOR_IP=$(curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || echo "127.0.0.1")
  DESTROY_ARGS+=(-var="operator_ip=$OPERATOR_IP" -var="alert_email=teardown@placeholder.com")
fi

# ---------------------------------------------------------------------------
# Phase 5: Terraform destroy
# ---------------------------------------------------------------------------
info "Running terraform destroy..."
if terraform -chdir="$TF_DIR" destroy "${DESTROY_ARGS[@]}"; then
  echo ""
  success "All NovaCrest lab resources have been destroyed."
  echo ""
  echo "  - OpenSearch Serverless charges have stopped."
  echo "  - Your terraform.tfvars has been preserved for future deployments."
  echo "  - Run ./scripts/setup.sh to redeploy."
else
  echo ""
  error "Terraform destroy failed. Check the output above."
  echo ""
  echo "  Common fixes:"
  echo "  - If 409 ConflictException on action group: run this script again"
  echo "  - If resources are stuck: terraform -chdir=terraform state rm <resource>"
  echo "  - Manual cleanup: check the AWS console for remaining resources"
  exit 1
fi

# ---------------------------------------------------------------------------
# Phase 6: Cleanup
# ---------------------------------------------------------------------------
rm -f "$TF_DIR/plan.out"
