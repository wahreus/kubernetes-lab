#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"

AWS_REGION="${AWS_REGION:-eu-north-1}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is not installed or not in PATH."
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is not installed or not in PATH."
  exit 1
fi

if [[ ! -d "$TF_DIR" ]]; then
  echo "Terraform directory not found: $TF_DIR"
  exit 1
fi

CURRENT_IP="$(curl -fsS https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -n "$CURRENT_IP" ]]; then
  ALLOWED_CIDR="${ALLOWED_CIDR:-$CURRENT_IP/32}"
else
  ALLOWED_CIDR="${ALLOWED_CIDR:-0.0.0.0/0}"
  echo "Could not detect public IP. Falling back to ALLOWED_CIDR=$ALLOWED_CIDR"
fi

echo "Destroying Kubernetes lab resources..."
echo "Using AWS region:       $AWS_REGION"
echo "Using public key:       $PUBLIC_KEY_PATH"
echo "Allowed access CIDR:    $ALLOWED_CIDR"
echo

terraform -chdir="$TF_DIR" init

terraform -chdir="$TF_DIR" destroy \
  -var "aws_region=$AWS_REGION" \
  -var "public_key_path=$PUBLIC_KEY_PATH" \
  -var "allowed_ssh_cidr=$ALLOWED_CIDR" \
  -auto-approve

echo
echo "Removing local files created by build_lab.sh..."

rm -f "$ROOT_DIR/ssh_config"
rm -f "$ROOT_DIR/lab_hosts.txt"

echo
echo "Lab destroyed."