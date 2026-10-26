#!/usr/bin/env bash
# =============================================
# Firecracker CLI - Simple & User Friendly
# =============================================

set -euo pipefail

SOCKET="/var/run/firecracker.sock"
COMMAND="${1:-help}"

usage() {
  cat <<EOF
Firecracker CLI

Usage: $0 <command> [options]

Commands:
  start          Start the microVM (InstanceStart)
  pause          Pause the microVM
  resume         Resume a paused microVM
  shutdown       Graceful shutdown (SendCtrlAltDel)
  metrics        Flush metrics
  help           Show this help message

Options:
  --socket PATH  Specify custom Firecracker socket path (default: ./firecracker.sock)

Examples:
  $0 start
  $0 shutdown
  $0 shutdown --socket /tmp/firecracker.sock
  $0 metrics
EOF
}

# Check socket
check_socket() {
  if [[ ! -S "$SOCKET" ]]; then
    echo "Error: Firecracker socket not found at: $SOCKET" >&2
    echo "Make sure Firecracker is running and the socket exists." >&2
    exit 1
  fi
}

# Send action to Firecracker
send_action() {
  local action=$1
  check_socket

  echo "Sending action: $action ..."

  curl --unix-socket "$SOCKET" -s -i \
    -X PUT "http://localhost/actions" \
    -H "Content-Type: application/json" \
    -d "{\"action_type\": \"$action\"}"

  echo
}

# Pause or resume the microVM
patch_vm() {
  local state=$1
  check_socket

  echo "Setting VM state: $state ..."

  curl --unix-socket "$SOCKET" -s -i \
    -X PATCH "http://localhost/vm" \
    -H "Content-Type: application/json" \
    -d "{\"state\": \"$state\"}"

  echo
}

case "$COMMAND" in
  start)
    send_action "InstanceStart"
    ;;

  pause)
    patch_vm "Paused"
    ;;

  resume)
    patch_vm "Resumed"
    ;;

  shutdown)
    send_action "SendCtrlAltDel"
    ;;

  metrics)
    send_action "FlushMetrics"
    ;;

  help|--help|-h)
    usage
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    echo
    usage
    exit 1
    ;;
esac
