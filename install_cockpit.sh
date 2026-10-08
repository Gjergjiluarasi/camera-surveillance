#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as your regular user, without sudo."
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the operating system."
  exit 1
fi

. /etc/os-release

if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "26.04" ]]; then
  echo "Unsupported OS: ${PRETTY_NAME:-unknown}. This script targets Ubuntu 26.04."
  exit 1
fi

arch="$(dpkg --print-architecture)"
case "$arch" in
  amd64|arm64) ;;
  *)
    echo "Unsupported architecture: $arch. This script supports amd64 and arm64."
    exit 1
    ;;
esac

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl is not available; Cockpit requires a systemd-based Ubuntu system."
  exit 1
fi

sudo apt-get update
sudo apt-get install -y cockpit
sudo systemctl enable --now cockpit.socket

echo "Cockpit installed and enabled. Open https://$(hostname -f 2>/dev/null || hostname):9090/"
echo "Sign in with a local Ubuntu account. This script does not change firewall rules."