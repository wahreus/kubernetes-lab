#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"

AWS_REGION="${AWS_REGION:-eu-north-1}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}"
CONTROL_PLANE_INSTANCE_TYPE="${CONTROL_PLANE_INSTANCE_TYPE:-t3.medium}"
WORKER_INSTANCE_TYPE="${WORKER_INSTANCE_TYPE:-t3.small}"
ROOT_VOLUME_SIZE="${ROOT_VOLUME_SIZE:-30}"

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

if [[ -n "${SSH_ALLOWED_CIDR:-}" ]]; then
  ALLOWED_CIDR="$SSH_ALLOWED_CIDR"
  echo "Using manually supplied SSH_ALLOWED_CIDR: $ALLOWED_CIDR"
elif [[ -n "$CURRENT_IP" ]]; then
  ALLOWED_CIDR="$CURRENT_IP/32"
  echo "Detected current public IP: $CURRENT_IP"
else
  echo "Could not detect public IP."
  echo "Set SSH_ALLOWED_CIDR manually, for example:"
  echo "  SSH_ALLOWED_CIDR=1.2.3.4/32 ./build_lab.sh"
  exit 1
fi

echo "Destroying Kubernetes lab resources..."
echo "Using AWS region:                  $AWS_REGION"
echo "Using public key:                  $PUBLIC_KEY_PATH"
echo "Allowed access CIDR:               $ALLOWED_CIDR"
echo "Control plane instance type:       $CONTROL_PLANE_INSTANCE_TYPE"
echo "Worker instance type:              $WORKER_INSTANCE_TYPE"
echo "Root volume size:                  ${ROOT_VOLUME_SIZE} GiB"
echo

terraform -chdir="$TF_DIR" init

terraform -chdir="$TF_DIR" destroy \
  -var "aws_region=$AWS_REGION" \
  -var "public_key_path=$PUBLIC_KEY_PATH" \
  -var "allowed_ssh_cidr=$ALLOWED_CIDR" \
  -var "control_plane_instance_type=$CONTROL_PLANE_INSTANCE_TYPE" \
  -var "worker_instance_type=$WORKER_INSTANCE_TYPE" \
  -var "root_volume_size=$ROOT_VOLUME_SIZE" \
  -auto-approve

echo
echo "Removing local files created by build_lab.sh..."

rm -f "$ROOT_DIR/ssh_config"
rm -f "$ROOT_DIR/lab_hosts.txt"
rm -f "$ROOT_DIR/.known_hosts"

echo "Removing local Terraform state files..."
rm -f "$TF_DIR/terraform.tfstate"
rm -f "$TF_DIR/terraform.tfstate.backup"
rm -f "$ROOT_DIR/terraform.tfstate"
rm -f "$ROOT_DIR/terraform.tfstate.backup"

echo
echo "Lab destroyed."
