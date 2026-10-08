#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

if [[ "$EUID" -eq 0 ]]; then
  log_err "Run as your regular user, without sudo: ./install_ethercat_igh.sh"
fi

if [[ ! -r /etc/os-release ]]; then
  log_err "Cannot identify the operating system. This installer targets Ubuntu 26.04."
fi
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "26.04" || "${VERSION_CODENAME:-}" != "resolute" ]]; then
  log_err "Unsupported OS: ${PRETTY_NAME:-unknown}. This installer targets Ubuntu 26.04 (Resolute)."
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64|arm64) ;;
  *) log_err "Unsupported architecture: $ARCH. Supported architectures are amd64 and arm64." ;;
esac

MASTER0_DEVICE=${MASTER0_DEVICE:-}
if [[ -z "$MASTER0_DEVICE" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Dedicated EtherCAT interface name or MAC address: " MASTER0_DEVICE
  else
    log_err "Set MASTER0_DEVICE to the dedicated EtherCAT NIC name or MAC address."
  fi
fi

if [[ ! "$MASTER0_DEVICE" =~ ^[[:alnum:]_.:-]+$ ]]; then
  log_err "Invalid MASTER0_DEVICE value: $MASTER0_DEVICE"
fi
if [[ ! "$MASTER0_DEVICE" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] && ! ip link show dev "$MASTER0_DEVICE" >/dev/null 2>&1; then
  log_err "Network interface '$MASTER0_DEVICE' was not found. Use an existing dedicated NIC name or its MAC address."
fi

KERNEL_RELEASE=$(uname -r)
KERNEL_BUILD_DIR="/lib/modules/${KERNEL_RELEASE}/build"
if [[ ! -e "$KERNEL_BUILD_DIR" ]]; then
  log_info "Installing development tools and headers for kernel ${KERNEL_RELEASE}..."
  sudo apt-get update
  sudo apt-get install -y \
    autoconf \
    automake \
    build-essential \
    git \
    libtool \
    pkg-config \
    udev \
    "linux-headers-${KERNEL_RELEASE}"
else
  log_info "Installing IgH build dependencies..."
  sudo apt-get update
  sudo apt-get install -y \
    autoconf \
    automake \
    build-essential \
    git \
    libtool \
    pkg-config \
    udev
fi

if [[ ! -e "$KERNEL_BUILD_DIR" ]]; then
  log_err "Kernel headers are missing at ${KERNEL_BUILD_DIR}. Install headers matching 'uname -r' and rerun."
fi

BUILD_ROOT=$(mktemp -d)
trap 'rm -rf "$BUILD_ROOT"' EXIT
log_info "Building IgH EtherCAT Master stable-1.6 for kernel ${KERNEL_RELEASE}..."
git clone --depth 1 --branch stable-1.6 https://gitlab.com/etherlab.org/ethercat.git "$BUILD_ROOT/ethercat"
cd "$BUILD_ROOT/ethercat"
./bootstrap
./configure \
  --prefix=/usr \
  --sysconfdir=/etc \
  --with-linux-dir="$KERNEL_BUILD_DIR" \
  --enable-generic
make -j"$(nproc)" all modules
sudo make modules_install
sudo make install
sudo depmod -a "$KERNEL_RELEASE"
sudo ldconfig

if [[ -f /etc/ethercat.conf ]]; then
  BACKUP="/etc/ethercat.conf.backup.$(date +%Y%m%d%H%M%S)"
  sudo cp -a /etc/ethercat.conf "$BACKUP"
  log_warn "Existing configuration backed up to ${BACKUP}."
fi
sudo tee /etc/ethercat.conf >/dev/null <<EOF
# IgH EtherCAT Master configuration. Use a dedicated NIC for EtherCAT.
MASTER0_DEVICE="${MASTER0_DEVICE}"
MASTER0_BACKUP=""
DEVICE_MODULES="generic"
UPDOWN_INTERFACES=""
EOF

if ! getent group ethercat >/dev/null; then
  sudo groupadd --system ethercat
fi
sudo usermod -aG ethercat "$(id -un)"
sudo tee /etc/udev/rules.d/99-EtherCAT.rules >/dev/null <<'EOF'
KERNEL=="EtherCAT[0-9]*", GROUP="ethercat", MODE="0660"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo systemctl daemon-reload

if ! systemctl cat ethercat.service >/dev/null 2>&1; then
  log_err "IgH installed, but systemd could not find ethercat.service. Check the upstream install output before starting the master."
fi

log_info "IgH EtherCAT Master installed and configured for ${MASTER0_DEVICE}."
log_info "The master was not started or enabled automatically. Review /etc/ethercat.conf, then run: sudo systemctl start ethercat"
log_info "Log out and back in for the ethercat group membership to take effect."
log_warn "Confirm this NIC is dedicated to EtherCAT; starting the master takes control of it."