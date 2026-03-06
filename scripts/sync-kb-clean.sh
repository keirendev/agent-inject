#!/usr/bin/env bash
# sync-kb-clean.sh — Sync legitimate KB documents to S3 and trigger re-ingestion
#
# Uploads only clean (legitimate) documents to the KB S3 bucket and triggers
# the Bedrock Knowledge Base data source to re-sync.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"

# Color helpers
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [[ ! -t 1 ]]; then GREEN='' BLUE='' BOLD='' NC=''; fi

info()    { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }

# Get bucket name and KB ID from Terraform outputs
BUCKET=$(cd "$TF_DIR" && terraform output -raw kb_bucket_name)
KB_ID=$(cd "$TF_DIR" && terraform output -raw knowledge_base_id)

info "Syncing clean KB docs to s3://${BUCKET}/"
aws s3 sync "$REPO_ROOT/knowledge-base-docs/clean/" "s3://${BUCKET}/" --delete
success "Clean docs uploaded."

info "Triggering KB data source re-ingestion..."
DATA_SOURCES=$(aws bedrock-agent list-data-sources \
    --knowledge-base-id "$KB_ID" \
    --query 'dataSourceSummaries[].dataSourceId' \
    --output text)

RED='\033[0;31m'
if [[ ! -t 1 ]]; then RED=''; fi

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
success "KB sync complete. Documents are indexed and ready."
