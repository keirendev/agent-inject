#!/usr/bin/env bash
# setup.sh — One-command deployment of the NovaCrest AI Security Lab
#
# Checks prerequisites, gathers configuration, and deploys the secure baseline
# via Terraform. Run from the repo root or any directory.
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
# Phase 1: Prerequisite checks
# ---------------------------------------------------------------------------
info "Checking prerequisites..."
MISSING=0

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    error "$1 is not installed. $2"
    MISSING=1
  else
    success "$1 found ($(command -v "$1"))"
  fi
}

check_cmd "aws"       "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
check_cmd "terraform" "Install: https://developer.hashicorp.com/terraform/install"
check_cmd "python3"   "Install Python 3.x: https://www.python.org/downloads/"
check_cmd "jq"        "Install: https://jqlang.github.io/jq/download/"
check_cmd "curl"      "Install via your package manager"

# Check Terraform version >= 1.5
if command -v terraform &>/dev/null; then
  TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo "0.0.0")
  TF_MAJOR=$(echo "$TF_VERSION" | cut -d. -f1)
  TF_MINOR=$(echo "$TF_VERSION" | cut -d. -f2)
  if [[ "$TF_MAJOR" -lt 1 ]] || { [[ "$TF_MAJOR" -eq 1 ]] && [[ "$TF_MINOR" -lt 5 ]]; }; then
    error "Terraform >= 1.5 required (found $TF_VERSION)"
    MISSING=1
  fi
fi

if [[ "$MISSING" -ne 0 ]]; then
  echo ""
  error "Missing prerequisites. Install them and retry."
  exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# Phase 2: AWS credential check
# ---------------------------------------------------------------------------
info "Checking AWS credentials..."
if ! AWS_IDENTITY=$(aws sts get-caller-identity --output json 2>&1); then
  error "AWS credentials not configured."
  echo "  Run: aws configure"
  echo "  Or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables."
  exit 1
fi

AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | jq -r '.Account')
AWS_USER_ARN=$(echo "$AWS_IDENTITY" | jq -r '.Arn')
success "Authenticated as $AWS_USER_ARN (account $AWS_ACCOUNT)"
echo ""

# ---------------------------------------------------------------------------
# Phase 3: Gather configuration
# ---------------------------------------------------------------------------
info "Gathering configuration..."

# Source .env if it exists (for defaults)
if [[ -f "$REPO_ROOT/.env" ]]; then
  info "Loading defaults from .env"
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

# --- Operator IP ---
OPERATOR_IP="${OPERATOR_IP:-}"
if [[ -z "$OPERATOR_IP" ]]; then
  DETECTED_IP=$(curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]') || true
  if [[ "$DETECTED_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OPERATOR_IP="$DETECTED_IP"
    info "Auto-detected operator IP: $OPERATOR_IP"
  elif [[ -t 0 ]]; then
    read -rp "Enter your public IP (for security group allowlisting): " OPERATOR_IP
  else
    error "Could not detect operator IP. Set OPERATOR_IP environment variable."
    exit 1
  fi
fi

# --- Alert email ---
ALERT_EMAIL="${ALERT_EMAIL:-}"
if [[ -z "$ALERT_EMAIL" ]]; then
  if [[ -t 0 ]]; then
    read -rp "Enter alert email (for billing alerts): " ALERT_EMAIL
  else
    error "ALERT_EMAIL not set. Set it as an environment variable."
    exit 1
  fi
fi

# --- AWS Region ---
AWS_REGION="${AWS_REGION:-}"
if [[ -z "$AWS_REGION" ]]; then
  AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
  if [[ -z "$AWS_REGION" ]]; then
    if [[ -t 0 ]]; then
      read -rp "Enter AWS region [ap-southeast-2]: " AWS_REGION
      AWS_REGION="${AWS_REGION:-ap-southeast-2}"
    else
      AWS_REGION="ap-southeast-2"
    fi
  fi
fi

echo ""
printf "${BOLD}Configuration summary:${NC}\n"
echo "  Operator IP:  $OPERATOR_IP"
echo "  Alert email:  $ALERT_EMAIL"
echo "  AWS region:   $AWS_REGION"
echo "  AWS account:  $AWS_ACCOUNT"
echo ""

# ---------------------------------------------------------------------------
# Phase 4: Generate terraform.tfvars
# ---------------------------------------------------------------------------
TFVARS_FILE="$TF_DIR/terraform.tfvars"

if [[ -f "$TFVARS_FILE" ]]; then
  warn "terraform.tfvars already exists."
  if [[ -t 0 ]]; then
    read -rp "Overwrite? (y/N): " OVERWRITE
    if [[ "${OVERWRITE,,}" != "y" ]]; then
      info "Keeping existing terraform.tfvars"
    else
      info "Overwriting terraform.tfvars"
    fi
  fi
fi

if [[ ! -f "$TFVARS_FILE" ]] || [[ "${OVERWRITE:-}" == "y" ]]; then
  cat > "$TFVARS_FILE" <<EOF
# Auto-generated by setup.sh — do not commit (gitignored)
operator_ip = "$OPERATOR_IP"
alert_email = "$ALERT_EMAIL"
aws_region  = "$AWS_REGION"
EOF
  success "Generated $TFVARS_FILE"
fi

# ---------------------------------------------------------------------------
# Phase 5: Terraform init
# ---------------------------------------------------------------------------
echo ""
info "Initializing Terraform..."
terraform -chdir="$TF_DIR" init

# ---------------------------------------------------------------------------
# Phase 6: Terraform plan
# ---------------------------------------------------------------------------
echo ""
info "Planning deployment (secure baseline)..."
if ! terraform -chdir="$TF_DIR" plan \
  -var-file=scenarios/secure-baseline.tfvars \
  -var "operator_ip=$OPERATOR_IP" \
  -out=plan.out; then
  error "Terraform plan failed."
  echo ""
  echo "  Common causes:"
  echo "  - Bedrock model access not enabled (check the AWS console under Bedrock > Model access)"
  echo "  - Required models: amazon.nova-lite-v1:0, amazon.titan-embed-text-v2:0"
  echo "  - Region '$AWS_REGION' may not support all required services"
  exit 1
fi

# ---------------------------------------------------------------------------
# Phase 7: Cost warning + confirmation
# ---------------------------------------------------------------------------
echo ""
printf "${YELLOW}${BOLD}COST WARNING${NC}\n"
echo "  This will create AWS resources including:"
echo "  - OpenSearch Serverless collection (~\$11.52/day — the biggest cost driver)"
echo "  - Bedrock Agent, Knowledge Base, Guardrails"
echo "  - EC2 instance (t3.micro), Lambda, S3, DynamoDB, CloudWatch"
echo ""
echo "  Estimated cost: \$15-30/day while running."
echo "  Run ./scripts/teardown.sh when done to stop charges."
echo ""

if [[ -t 0 ]]; then
  read -rp "Proceed with deployment? (yes/no): " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    info "Aborted. Run this script again when ready."
    rm -f "$TF_DIR/plan.out"
    exit 0
  fi
else
  warn "Non-interactive mode — proceeding without confirmation."
fi

# ---------------------------------------------------------------------------
# Phase 8: Terraform apply
# ---------------------------------------------------------------------------
echo ""
info "Deploying NovaCrest AI Security Lab..."
if ! terraform -chdir="$TF_DIR" apply plan.out; then
  error "Terraform apply failed. Check output above for details."
  echo ""
  echo "  If Bedrock returns 'Access denied', ensure model access is enabled:"
  echo "  AWS Console > Bedrock > Model access > Manage model access"
  exit 1
fi

# ---------------------------------------------------------------------------
# Phase 9: Display outputs
# ---------------------------------------------------------------------------
echo ""
printf "${GREEN}${BOLD}Deployment complete!${NC}\n"
echo ""

FRONTEND_URL=$(terraform -chdir="$TF_DIR" output -raw frontend_url 2>/dev/null || echo "N/A")
AGENT_ID=$(terraform -chdir="$TF_DIR" output -raw agent_id 2>/dev/null || echo "N/A")
AGENT_ALIAS=$(terraform -chdir="$TF_DIR" output -raw agent_alias_id 2>/dev/null || echo "N/A")
KB_BUCKET=$(terraform -chdir="$TF_DIR" output -raw kb_bucket_name 2>/dev/null || echo "N/A")
DASHBOARD_URL=$(terraform -chdir="$TF_DIR" output -raw dashboard_url 2>/dev/null || echo "N/A")

echo "  Frontend URL:     $FRONTEND_URL"
echo "  Agent ID:         $AGENT_ID"
echo "  Agent Alias ID:   $AGENT_ALIAS"
echo "  KB Bucket:        $KB_BUCKET"
echo "  Dashboard:        $DASHBOARD_URL"
echo ""
warn "Wait 2-3 minutes for the EC2 instance to finish setup before accessing the frontend."
echo ""
info "If the agent doesn't respond, verify Bedrock model access is enabled:"
echo "  AWS Console > Bedrock > Model access"
echo "  Required models: amazon.nova-lite-v1:0, amazon.titan-embed-text-v2:0"
echo ""
printf "${YELLOW}${BOLD}REMINDER:${NC} Run ${BOLD}./scripts/teardown.sh${NC} when done to stop ongoing charges.\n"
