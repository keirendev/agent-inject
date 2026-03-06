#!/usr/bin/env bash
# sync-kb-poisoned.sh — Sync poisoned KB documents alongside clean docs
#
# Uploads clean docs first, then adds poisoned documents into the same S3
# prefixes so they get indexed by the KB. Poisoned docs contain hidden
# injection payloads for demonstrating indirect prompt injection attacks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
POISONED_DIR="$REPO_ROOT/knowledge-base-docs/poisoned"

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

# Get bucket name and KB ID from Terraform outputs
BUCKET=$(cd "$TF_DIR" && terraform output -raw kb_bucket_name)
KB_ID=$(cd "$TF_DIR" && terraform output -raw knowledge_base_id)

warn "This will upload POISONED documents to the KB bucket."
echo "  These contain injection payloads for security testing."
echo ""

info "Syncing clean docs first..."
aws s3 sync "$REPO_ROOT/knowledge-base-docs/clean/" "s3://${BUCKET}/"
success "Clean docs uploaded."

info "Adding poisoned docs..."
# Place poisoned docs in the same prefixes as their clean counterparts
# so they get retrieved when users ask about those topics
aws s3 cp "$POISONED_DIR/product-faq-injected.md" \
    "s3://${BUCKET}/product-docs/product-faq-updated.md"
aws s3 cp "$POISONED_DIR/refund-policy-injected.md" \
    "s3://${BUCKET}/support-policies/refund-policy-updated-jan2026.md"
aws s3 cp "$POISONED_DIR/onboarding-guide-injected.md" \
    "s3://${BUCKET}/internal/onboarding-guide.md"
# Overwrite clean pricing doc with poisoned version (simulates supply-chain attack)
aws s3 cp "$POISONED_DIR/pricing-tiers-injected.md" \
    "s3://${BUCKET}/product-docs/pricing-tiers.md"
success "Poisoned docs uploaded (pricing-tiers.md overwritten with deceptive prices)."

info "Triggering KB data source re-ingestion..."
DATA_SOURCES=$(aws bedrock-agent list-data-sources \
    --knowledge-base-id "$KB_ID" \
    --query 'dataSourceSummaries[].dataSourceId' \
    --output text)

for DS_ID in $DATA_SOURCES; do
    info "Starting ingestion for data source: ${DS_ID}"
    JOB_ID=$(aws bedrock-agent start-ingestion-job \
        --knowledge-base-id "$KB_ID" \
        --data-source-id "$DS_ID" \
        --output text \
        --query 'ingestionJob.ingestionJobId')
    info "Ingestion job started: ${JOB_ID}"

    info "Waiting for ingestion to complete..."
    ELAPSED=0
    TIMEOUT=300
    while true; do
        STATUS=$(aws bedrock-agent get-ingestion-job \
            --knowledge-base-id "$KB_ID" \
            --data-source-id "$DS_ID" \
            --ingestion-job-id "$JOB_ID" \
            --query 'ingestionJob.status' --output text)
        case "$STATUS" in
            COMPLETE)
                success "Ingestion complete for data source ${DS_ID}."
                break
                ;;
            FAILED)
                echo -e "${RED}[ERROR]${NC} Ingestion FAILED for data source ${DS_ID}."
                exit 1
                ;;
            *)
                if (( ELAPSED >= TIMEOUT )); then
                    echo -e "${RED}[ERROR]${NC} Ingestion timed out after ${TIMEOUT}s (status: ${STATUS})."
                    exit 1
                fi
                printf "  Status: %s (elapsed %ds)...\r" "$STATUS" "$ELAPSED"
                sleep 15
                ELAPSED=$((ELAPSED + 15))
                ;;
        esac
    done
done

echo ""
success "Poisoned KB sync complete. Documents are indexed and ready for testing."
echo ""
echo -e "  ${RED}REMINDER${NC}: Run ./scripts/sync-kb-clean.sh to restore clean docs when done testing."
