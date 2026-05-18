#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"

AWS_REGION="${AWS_REGION:-eu-north-1}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-ubuntu}"
OPEN_TERMINALS="${OPEN_TERMINALS:-true}"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is not installed or not in PATH."
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is not installed or not in PATH."
  exit 1
fi

if [[ ! -f "$PUBLIC_KEY_PATH" ]]; then
  echo "SSH public key not found: $PUBLIC_KEY_PATH"
  echo "Create one with: ssh-keygen -t ed25519 -C \"k8s-lab\""
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH private key not found: $SSH_KEY"
  echo "Set SSH_KEY=/path/to/private/key if you use another key."
  exit 1
fi

CURRENT_IP="$(curl -fsS https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -n "$CURRENT_IP" ]]; then
  ALLOWED_CIDR="${ALLOWED_CIDR:-$CURRENT_IP/32}"
else
  ALLOWED_CIDR="${ALLOWED_CIDR:-0.0.0.0/0}"
  echo "Could not detect public IP. Falling back to ALLOWED_CIDR=$ALLOWED_CIDR"
fi

echo "Using AWS region:       $AWS_REGION"
echo "Using public key:       $PUBLIC_KEY_PATH"
echo "Using SSH key:          $SSH_KEY"
echo "Allowed access CIDR:    $ALLOWED_CIDR"
echo

terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" apply \
  -var "aws_region=$AWS_REGION" \
  -var "public_key_path=$PUBLIC_KEY_PATH" \
  -var "allowed_ssh_cidr=$ALLOWED_CIDR" \
  -auto-approve

CONTROL_IP="$(terraform -chdir="$TF_DIR" output -raw control_plane_public_ip)"
WORKER_IP="$(terraform -chdir="$TF_DIR" output -raw worker_public_ip)"

cat > "$ROOT_DIR/ssh_config" <<CONFIG
Host k8s-control-plane
  HostName $CONTROL_IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new

Host k8s-worker
  HostName $WORKER_IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
CONFIG

cat > "$ROOT_DIR/lab_hosts.txt" <<HOSTS
control-plane public:  $CONTROL_IP
worker public:         $WORKER_IP

SSH commands:
ssh -F $ROOT_DIR/ssh_config k8s-control-plane
ssh -F $ROOT_DIR/ssh_config k8s-worker
HOSTS

wait_for_ssh() {
  local host="$1"
  echo "Waiting for SSH on $host..."
  until ssh -F "$ROOT_DIR/ssh_config" \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    "$host" "echo connected" >/dev/null 2>&1; do
    sleep 5
  done
}

wait_for_ssh k8s-control-plane
wait_for_ssh k8s-worker

echo
echo "Lab is ready. Details written to:"
echo "  $ROOT_DIR/lab_hosts.txt"
echo "  $ROOT_DIR/ssh_config"
echo
cat "$ROOT_DIR/lab_hosts.txt"

if [[ "$OPEN_TERMINALS" == "true" ]]; then
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    osascript <<APPLESCRIPT
      tell application "Terminal"
        do script "ssh -F '$ROOT_DIR/ssh_config' k8s-control-plane"
        do script "ssh -F '$ROOT_DIR/ssh_config' k8s-worker"
        activate
      end tell
APPLESCRIPT
  else
    echo "Automatic terminal opening is currently implemented for macOS Terminal."
    echo "Open these manually:"
    echo "  ssh -F $ROOT_DIR/ssh_config k8s-control-plane"
    echo "  ssh -F $ROOT_DIR/ssh_config k8s-worker"
  fi
fi
