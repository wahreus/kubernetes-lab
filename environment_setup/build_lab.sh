#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"

AWS_REGION="${AWS_REGION:-eu-north-1}"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS:-$ROOT_DIR/.known_hosts}"
SSH_WAIT_TIMEOUT_SECONDS="${SSH_WAIT_TIMEOUT_SECONDS:-300}"
OPEN_TERMINALS="${OPEN_TERMINALS:-true}"
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

echo "Using AWS region:                  $AWS_REGION"
echo "Using public key:                  $PUBLIC_KEY_PATH"
echo "Using SSH key:                     $SSH_KEY"
echo "Using known hosts file:            $SSH_KNOWN_HOSTS"
echo "SSH wait timeout:                 ${SSH_WAIT_TIMEOUT_SECONDS}s"
echo "Allowed access CIDR:               $ALLOWED_CIDR"
echo "Control plane instance type:       $CONTROL_PLANE_INSTANCE_TYPE"
echo "Worker instance type:              $WORKER_INSTANCE_TYPE"
echo "Root volume size:                  ${ROOT_VOLUME_SIZE} GiB"
echo

terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" apply \
  -var "aws_region=$AWS_REGION" \
  -var "public_key_path=$PUBLIC_KEY_PATH" \
  -var "allowed_ssh_cidr=$ALLOWED_CIDR" \
  -var "control_plane_instance_type=$CONTROL_PLANE_INSTANCE_TYPE" \
  -var "worker_instance_type=$WORKER_INSTANCE_TYPE" \
  -var "root_volume_size=$ROOT_VOLUME_SIZE" \
  -auto-approve

CONTROL_IP="$(terraform -chdir="$TF_DIR" output -raw control_plane_public_ip)"
WORKER_A_IP="$(terraform -chdir="$TF_DIR" output -raw worker_a_public_ip)"
WORKER_B_IP="$(terraform -chdir="$TF_DIR" output -raw worker_b_public_ip)"
CONTROL_PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw control_plane_private_ip)"
WORKER_A_PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw worker_a_private_ip)"
WORKER_B_PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw worker_b_private_ip)"

# Use a lab-local known_hosts file so recreated EC2 instances do not get
# stuck on stale host keys from ~/.ssh/known_hosts.
rm -f "$SSH_KNOWN_HOSTS"
touch "$SSH_KNOWN_HOSTS"
chmod 600 "$SSH_KNOWN_HOSTS"

cat > "$ROOT_DIR/ssh_config" <<CONFIG
Host k8s-control-plane
  HostName $CONTROL_IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ${SSH_KNOWN_HOSTS}
  IdentitiesOnly yes

Host k8s-worker-a
  HostName $WORKER_A_IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ${SSH_KNOWN_HOSTS}
  IdentitiesOnly yes

Host k8s-worker-b
  HostName $WORKER_B_IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ${SSH_KNOWN_HOSTS}
  IdentitiesOnly yes
CONFIG

cat > "$ROOT_DIR/lab_hosts.txt" <<HOSTS
control-plane public:   $CONTROL_IP
control-plane private:  $CONTROL_PRIVATE_IP
worker-a public:        $WORKER_A_IP
worker-a private:       $WORKER_A_PRIVATE_IP
worker-b public:        $WORKER_B_IP
worker-b private:       $WORKER_B_PRIVATE_IP

SSH commands:
ssh -F $ROOT_DIR/ssh_config k8s-control-plane
ssh -F $ROOT_DIR/ssh_config k8s-worker-a
ssh -F $ROOT_DIR/ssh_config k8s-worker-b

Kubernetes API endpoint hint for kubeadm/kubectl access:
$CONTROL_IP:6443
HOSTS

wait_for_ssh() {
  local host="$1"
  local start_time
  local now
  local elapsed
  local attempt=1
  local last_error_file

  start_time="$(date +%s)"
  last_error_file="$(mktemp)"

  echo "Waiting for SSH on $host..."

  while true; do
    if ssh -F "$ROOT_DIR/ssh_config"       -o BatchMode=yes       -o ConnectTimeout=5       "$host" "echo connected" >/dev/null 2>"$last_error_file"; then
      rm -f "$last_error_file"
      echo "SSH is ready on $host."
      return 0
    fi

    now="$(date +%s)"
    elapsed=$((now - start_time))

    if (( elapsed >= SSH_WAIT_TIMEOUT_SECONDS )); then
      echo
      echo "Timed out waiting for SSH on $host after ${SSH_WAIT_TIMEOUT_SECONDS}s."
      echo "Last SSH error:"
      sed 's/^/  /' "$last_error_file" || true
      rm -f "$last_error_file"
      echo
      echo "Try this manually for more detail:"
      echo "  ssh -vvv -F $ROOT_DIR/ssh_config $host 'echo connected'"
      return 1
    fi

    if (( attempt % 6 == 0 )); then
      echo "Still waiting for SSH on $host... (${elapsed}s elapsed)"
    fi

    attempt=$((attempt + 1))
    sleep 5
  done
}

wait_for_ssh k8s-control-plane
wait_for_ssh k8s-worker-a
wait_for_ssh k8s-worker-b

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
        do script "ssh -F '$ROOT_DIR/ssh_config' k8s-worker-a"
        do script "ssh -F '$ROOT_DIR/ssh_config' k8s-worker-b"
        activate
      end tell
APPLESCRIPT
  else
    echo "Automatic terminal opening is currently implemented for macOS Terminal."
    echo "Open these manually:"
    echo "  ssh -F $ROOT_DIR/ssh_config k8s-control-plane"
    echo "  ssh -F $ROOT_DIR/ssh_config k8s-worker-a"
    echo "  ssh -F $ROOT_DIR/ssh_config k8s-worker-b"
  fi
fi
