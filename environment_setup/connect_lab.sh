#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_CONFIG="$ROOT_DIR/ssh_config"

if [[ ! -f "$SSH_CONFIG" ]]; then
  echo "SSH configuration not found: $SSH_CONFIG" >&2
  echo "Run ./build_lab.sh first." >&2
  exit 1
fi

if [[ "${OSTYPE:-}" == darwin* ]] && command -v osascript >/dev/null 2>&1; then
  osascript <<APPLESCRIPT
    tell application "Terminal"
      do script "ssh -F '$SSH_CONFIG' k8s-control-plane"
      do script "ssh -F '$SSH_CONFIG' k8s-worker-a"
      do script "ssh -F '$SSH_CONFIG' k8s-worker-b"
      activate
    end tell
APPLESCRIPT
else
  echo "Open the nodes with:"
  echo "  ssh -F $SSH_CONFIG k8s-control-plane"
  echo "  ssh -F $SSH_CONFIG k8s-worker-a"
  echo "  ssh -F $SSH_CONFIG k8s-worker-b"
fi
