#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
TFVARS_FILE="$TF_DIR/lab.auto.tfvars"

PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS:-$ROOT_DIR/.known_hosts}"
SSH_WAIT_TIMEOUT_SECONDS="${SSH_WAIT_TIMEOUT_SECONDS:-300}"
CLOUD_INIT_WAIT_TIMEOUT_SECONDS="${CLOUD_INIT_WAIT_TIMEOUT_SECONDS:-900}"
OPEN_TERMINALS="${OPEN_TERMINALS:-false}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || \
    fail "$command_name is not installed or not in PATH."
}

hcl_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "$value"
}

write_string_variable() {
  local name="$1"
  local value="$2"
  printf '%s = ' "$name" >>"$TFVARS_FILE"
  hcl_string "$value" >>"$TFVARS_FILE"
  printf '\n' >>"$TFVARS_FILE"
}

write_number_variable() {
  local name="$1"
  local value="$2"
  printf '%s = %s\n' "$name" "$value" >>"$TFVARS_FILE"
}

[[ -d "$TF_DIR" ]] || fail "Terraform directory not found: $TF_DIR"

for command_name in terraform aws curl ssh; do
  require_command "$command_name"
done

[[ -f "$PUBLIC_KEY_PATH" ]] || {
  echo "SSH public key not found: $PUBLIC_KEY_PATH"
  echo "Create one with: ssh-keygen -t ed25519 -C \"k8s-lab\""
  exit 1
}

[[ -f "$SSH_KEY" ]] || {
  echo "SSH private key not found: $SSH_KEY"
  echo "Set SSH_KEY=/path/to/private/key if you use another key."
  exit 1
}

PUBLIC_KEY_CONTENT="$(tr -d '\r\n' <"$PUBLIC_KEY_PATH")"
[[ -n "$PUBLIC_KEY_CONTENT" ]] || fail "SSH public key is empty: $PUBLIC_KEY_PATH"

if [[ -n "${ALLOWED_ACCESS_CIDR:-}" ]]; then
  ACCESS_CIDR="$ALLOWED_ACCESS_CIDR"
  echo "Using manually supplied ALLOWED_ACCESS_CIDR: $ACCESS_CIDR"
elif [[ -n "${SSH_ALLOWED_CIDR:-}" ]]; then
  ACCESS_CIDR="$SSH_ALLOWED_CIDR"
  echo "Using legacy SSH_ALLOWED_CIDR as ALLOWED_ACCESS_CIDR: $ACCESS_CIDR"
else
  CURRENT_IP="$(curl -fsS https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
  [[ -n "$CURRENT_IP" ]] || {
    echo "Could not detect your public IP."
    echo "Set ALLOWED_ACCESS_CIDR manually, for example:"
    echo "  ALLOWED_ACCESS_CIDR=1.2.3.4/32 ./build_lab.sh"
    exit 1
  }
  ACCESS_CIDR="$CURRENT_IP/32"
  echo "Detected current public IP: $CURRENT_IP"
fi

echo "Verifying AWS credentials..."
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || \
  fail "AWS credentials are unavailable or invalid."
echo "Using AWS account: $AWS_ACCOUNT_ID"

: >"$TFVARS_FILE"
write_string_variable "ssh_public_key" "$PUBLIC_KEY_CONTENT"
write_string_variable "allowed_access_cidr" "$ACCESS_CIDR"

# Terraform owns the defaults. These values are written only when the caller
# explicitly supplies an environment-variable override.
[[ -n "${AWS_REGION:-}" ]] && write_string_variable "aws_region" "$AWS_REGION"
[[ -n "${NAME_PREFIX:-}" ]] && write_string_variable "name_prefix" "$NAME_PREFIX"
[[ -n "${CONTROL_PLANE_INSTANCE_TYPE:-}" ]] && \
  write_string_variable "control_plane_instance_type" "$CONTROL_PLANE_INSTANCE_TYPE"
[[ -n "${WORKER_INSTANCE_TYPE:-}" ]] && \
  write_string_variable "worker_instance_type" "$WORKER_INSTANCE_TYPE"
[[ -n "${ROOT_VOLUME_SIZE:-}" ]] && write_number_variable "root_volume_size" "$ROOT_VOLUME_SIZE"
[[ -n "${KUBERNETES_MINOR_VERSION:-}" ]] && \
  write_string_variable "kubernetes_minor_version" "$KUBERNETES_MINOR_VERSION"
[[ -n "${CRICTL_VERSION:-}" ]] && write_string_variable "crictl_version" "$CRICTL_VERSION"

terraform fmt "$TFVARS_FILE" >/dev/null

echo
echo "Terraform variables written to: $TFVARS_FILE"
echo "Allowed access CIDR:            $ACCESS_CIDR"
echo "SSH private key:                $SSH_KEY"
echo "SSH wait timeout:               ${SSH_WAIT_TIMEOUT_SECONDS}s"
echo "Cloud-init wait timeout:        ${CLOUD_INIT_WAIT_TIMEOUT_SECONDS}s"
echo

terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" fmt -check -recursive
terraform -chdir="$TF_DIR" validate

apply_args=()
if [[ "$AUTO_APPROVE" == "true" ]]; then
  apply_args+=("-auto-approve")
elif [[ "$AUTO_APPROVE" != "false" ]]; then
  fail "AUTO_APPROVE must be true or false."
fi

terraform -chdir="$TF_DIR" apply "${apply_args[@]}"

CONTROL_IP="$(terraform -chdir="$TF_DIR" output -raw control_plane_public_ip)"
WORKER_A_IP="$(terraform -chdir="$TF_DIR" output -raw worker_a_public_ip)"
WORKER_B_IP="$(terraform -chdir="$TF_DIR" output -raw worker_b_public_ip)"
CONTROL_PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw control_plane_private_ip)"
WORKER_A_PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw worker_a_private_ip)"
WORKER_B_PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw worker_b_private_ip)"

# Use a lab-local known_hosts file so recreated EC2 instances do not get stuck
# on stale host keys from ~/.ssh/known_hosts.
rm -f "$SSH_KNOWN_HOSTS"
touch "$SSH_KNOWN_HOSTS"
chmod 600 "$SSH_KNOWN_HOSTS"

cat >"$ROOT_DIR/ssh_config" <<CONFIG
Host k8s-control-plane
  HostName $CONTROL_IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
  UserKnownHostsFile $SSH_KNOWN_HOSTS
  IdentitiesOnly yes

Host k8s-worker-a
  HostName $WORKER_A_IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
  UserKnownHostsFile $SSH_KNOWN_HOSTS
  IdentitiesOnly yes

Host k8s-worker-b
  HostName $WORKER_B_IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking accept-new
  UserKnownHostsFile $SSH_KNOWN_HOSTS
  IdentitiesOnly yes
CONFIG

cat >"$ROOT_DIR/lab_hosts.txt" <<HOSTS
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
    if ssh -F "$ROOT_DIR/ssh_config" \
      -o BatchMode=yes \
      -o ConnectTimeout=5 \
      "$host" "echo connected" >/dev/null 2>"$last_error_file"; then
      rm -f "$last_error_file"
      echo "SSH is ready on $host."
      return 0
    fi

    now="$(date +%s)"
    elapsed=$((now - start_time))

    if ((elapsed >= SSH_WAIT_TIMEOUT_SECONDS)); then
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

    if ((attempt % 6 == 0)); then
      echo "Still waiting for SSH on $host... (${elapsed}s elapsed)"
    fi

    attempt=$((attempt + 1))
    sleep 5
  done
}

wait_for_cloud_init() {
  local host="$1"

  echo "Waiting for cloud-init on $host..."

  if ssh -F "$ROOT_DIR/ssh_config" \
    -o BatchMode=yes \
    "$host" \
    "sudo timeout ${CLOUD_INIT_WAIT_TIMEOUT_SECONDS}s cloud-init status --wait"; then
    echo "Bootstrap completed on $host."
  else
    echo "Bootstrap failed or timed out on $host."
    echo "Cloud-init status and recent output:"
    ssh -F "$ROOT_DIR/ssh_config" "$host" \
      "sudo cloud-init status --long || true; sudo tail -n 80 /var/log/cloud-init-output.log || true" || true
    return 1
  fi
}

verify_node_tools() {
  local host="$1"

  echo "Verifying Kubernetes tools on $host..."
  ssh -F "$ROOT_DIR/ssh_config" \
    -o BatchMode=yes \
    "$host" \
    "command -v containerd crictl kubeadm kubelet kubectl >/dev/null && sudo systemctl is-active --quiet containerd"
}

for host in k8s-control-plane k8s-worker-a k8s-worker-b; do
  wait_for_ssh "$host"
done

for host in k8s-control-plane k8s-worker-a k8s-worker-b; do
  wait_for_cloud_init "$host"
  verify_node_tools "$host"
done

echo
echo "Lab is ready. Details written to:"
echo "  $ROOT_DIR/lab_hosts.txt"
echo "  $ROOT_DIR/ssh_config"
echo
cat "$ROOT_DIR/lab_hosts.txt"

if [[ "$OPEN_TERMINALS" == "true" ]]; then
  "$ROOT_DIR/connect_lab.sh"
elif [[ "$OPEN_TERMINALS" != "false" ]]; then
  fail "OPEN_TERMINALS must be true or false."
fi
