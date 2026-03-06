#!/usr/bin/env bash
# swap-scenario.sh — Switch between misconfiguration scenarios
#
# Usage: ./scripts/swap-scenario.sh <scenario-name>
# Example: ./scripts/swap-scenario.sh scenario-rag-poisoning
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
SCENARIOS_DIR="$TF_DIR/scenarios"

# Color helpers
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

SCENARIO="${1:-}"

if [[ -z "$SCENARIO" ]]; then
    echo -e "${BOLD}Usage:${NC} $0 <scenario-name>"
    echo ""
    echo "Available scenarios:"
    for f in "$SCENARIOS_DIR"/*.tfvars; do
        name=$(basename "$f" .tfvars)
        # Extract first comment line as description
        desc=$(grep '^# Scenario:' "$f" 2>/dev/null | head -1 | sed 's/^# Scenario: //')
        if [[ -n "$desc" ]]; then
            printf "  ${GREEN}%-35s${NC} %s\n" "$name" "$desc"
        else
            printf "  ${GREEN}%s${NC}\n" "$name"
        fi
    done
    exit 1
fi

TFVARS_FILE="$SCENARIOS_DIR/${SCENARIO}.tfvars"
if [[ ! -f "$TFVARS_FILE" ]]; then
    error "Scenario file not found: $TFVARS_FILE"
    echo ""
    echo "Available scenarios:"
    ls "$SCENARIOS_DIR"/*.tfvars 2>/dev/null | xargs -I {} basename {} .tfvars | sed 's/^/  /'
    exit 1
fi

echo ""
info "Switching to scenario: ${BOLD}${SCENARIO}${NC}"
echo ""
echo -e "${YELLOW}Active misconfigurations:${NC}"
grep -E '^\w+\s*=' "$TFVARS_FILE" | while IFS= read -r line; do
    var=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
    val=$(echo "$line" | cut -d'=' -f2 | tr -d ' "')
    # Highlight non-default (vulnerable) values
    case "$var" in
        enable_overpermissive_iam)  [[ "$val" == "true" ]]  && printf "  ${RED}%-35s${NC} %s\n" "$var" "$val" || printf "  %-35s %s\n" "$var" "$val" ;;
        guardrail_sensitivity)     [[ "$val" != "HIGH" ]]   && printf "  ${RED}%-35s${NC} %s\n" "$var" "$val" || printf "  %-35s %s\n" "$var" "$val" ;;
        kb_include_internal_docs)  [[ "$val" == "true" ]]   && printf "  ${RED}%-35s${NC} %s\n" "$var" "$val" || printf "  %-35s %s\n" "$var" "$val" ;;
        enable_refund_confirmation) [[ "$val" == "false" ]] && printf "  ${RED}%-35s${NC} %s\n" "$var" "$val" || printf "  %-35s %s\n" "$var" "$val" ;;
        use_weak_system_prompt)    [[ "$val" == "true" ]]   && printf "  ${RED}%-35s${NC} %s\n" "$var" "$val" || printf "  %-35s %s\n" "$var" "$val" ;;
        enable_excessive_tools)    [[ "$val" == "true" ]]   && printf "  ${RED}%-35s${NC} %s\n" "$var" "$val" || printf "  %-35s %s\n" "$var" "$val" ;;
        *) printf "  %-35s %s\n" "$var" "$val" ;;
    esac
done
echo ""

cd "$TF_DIR"
info "Running terraform apply..."
APPLY_EXIT=0
terraform apply -var-file="$TFVARS_FILE" -auto-approve 2>&1 || APPLY_EXIT=$?

if [ "$APPLY_EXIT" -ne 0 ]; then
  warn "Initial apply exited with code $APPLY_EXIT (likely provider inconsistency bug). Retrying..."
  terraform apply -var-file="$TFVARS_FILE" -auto-approve
else
  # Detect provider-caused drift (guardrail_configuration null bug)
  info "Verifying configuration convergence..."
  PLAN_EXIT=0
  terraform plan -var-file="$TFVARS_FILE" -detailed-exitcode -out=/dev/null >/dev/null 2>&1 || PLAN_EXIT=$?
  if [ "$PLAN_EXIT" -eq 2 ]; then
    warn "Detected configuration drift (known provider issue). Running corrective apply..."
    terraform apply -var-file="$TFVARS_FILE" -auto-approve
  fi
fi

echo ""
success "Scenario '${SCENARIO}' is now active."

# Remind about KB sync if needed
if grep -q 'kb_include_internal_docs.*=.*true' "$TFVARS_FILE" 2>/dev/null; then
    echo ""
    warn "This scenario includes internal docs in the KB."
    echo "  To sync poisoned docs: ./scripts/sync-kb-poisoned.sh"
    echo "  To sync clean docs:    ./scripts/sync-kb-clean.sh"
fi
