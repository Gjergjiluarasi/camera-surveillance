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

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Unsupported OS: ${PRETTY_NAME:-unknown}. This script supports Ubuntu."
  exit 1
fi

codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
arch="$(dpkg --print-architecture)"

case "${VERSION_ID:-}" in
  20.04|22.04|24.04|26.04) ;;
  *)
    echo "Unsupported Ubuntu version: ${VERSION_ID:-unknown}."
    exit 1
    ;;
esac

case "$arch" in
  amd64|arm64) ;;
  *)
    echo "Unsupported architecture: $arch. This script supports amd64 and arm64."
    exit 1
    ;;
esac

sudo apt-get update
sudo apt-get install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable --now docker

# Optional: allow the current user to run Docker without sudo.
# Membership in the docker group grants root-level privileges.
sudo usermod -aG docker "$(id -un)"

echo "Docker and Docker Compose installed."
echo "Log out and back in for docker-group access to take effect."
echo "Verify with: docker --version && docker compose version"
