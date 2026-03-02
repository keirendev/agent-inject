#!/usr/bin/env bash
# run-tests.sh — Run the automated test harness against the deployed agent
#
# Usage:
#   ./scripts/run-tests.sh <scenario-name>        # run one scenario
#   ./scripts/run-tests.sh --all                   # run all scenarios
#   ./scripts/run-tests.sh --dry-run --all         # validate YAML only
#   ./scripts/run-tests.sh <scenario> --verbose    # with conversation output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"
RUNNER="$TESTS_DIR/test_runner.py"

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

# Check Python is available
if ! command -v python3 &>/dev/null; then
    error "python3 not found. Install Python 3.11+ to run the test harness."
    exit 1
fi

# Activate venv if present
if [[ -d "$REPO_ROOT/venv" ]]; then
    info "Activating virtualenv..."
    source "$REPO_ROOT/venv/bin/activate"
elif [[ -d "$REPO_ROOT/.venv" ]]; then
    info "Activating virtualenv..."
    source "$REPO_ROOT/.venv/bin/activate"
fi

# Check dependencies
if ! python3 -c "import yaml" 2>/dev/null; then
    warn "PyYAML not installed. Installing test dependencies..."
    pip install -q -r "$TESTS_DIR/requirements.txt"
fi

# Parse arguments — extract scenario name or pass through to test_runner
ARGS=()
SCENARIO=""
for arg in "$@"; do
    case "$arg" in
        --all|--dry-run|--verbose|-v|-a)
            ARGS+=("$arg")
            ;;
        --*)
            ARGS+=("$arg")
            ;;
        *)
            if [[ -z "$SCENARIO" ]]; then
                SCENARIO="$arg"
            else
                ARGS+=("$arg")
            fi
            ;;
    esac
done

if [[ -n "$SCENARIO" ]]; then
    ARGS=("--scenario" "$SCENARIO" "${ARGS[@]}")
fi

if [[ ${#ARGS[@]} -eq 0 ]]; then
    echo -e "${BOLD}Usage:${NC} $0 <scenario-name> [options]"
    echo ""
    echo "Examples:"
    echo "  $0 secure-baseline                Run baseline tests"
    echo "  $0 scenario-rag-poisoning         Run RAG poisoning tests"
    echo "  $0 --all                          Run all test definitions"
    echo "  $0 --all --dry-run                Validate YAML only"
    echo "  $0 scenario-prompt-leakage -v     Verbose output"
    echo ""
    echo "Available test definitions:"
    for f in "$TESTS_DIR"/definitions/*.yaml; do
        name=$(basename "$f" .yaml)
        printf "  ${GREEN}%s${NC}\n" "$name"
    done
    exit 1
fi

echo ""
info "NovaCrest AI Security Lab — Test Runner"
echo ""

python3 "$RUNNER" "${ARGS[@]}"
