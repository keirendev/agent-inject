#!/usr/bin/env bash
# get-my-ip.sh — Fetch operator's current public IP for security group allowlisting
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ ! -t 1 ]]; then RED='' GREEN='' BLUE='' NC=''; fi

info()  { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

ip=$(curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]') || true

if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  error "Could not detect a valid public IP address."
  echo "  Received: '$ip'"
  echo "  Try manually: curl -s https://checkip.amazonaws.com"
  exit 1
fi

echo "$ip"
info "Use this IP for operator_ip when deploying:"
echo "  export OPERATOR_IP=$ip"
