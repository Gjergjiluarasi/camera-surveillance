#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { printf '%b[INFO]%b %s\n' "$GREEN" "$NC" "$*"; }
log_warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
log_err()  { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

if [[ "$EUID" -eq 0 ]]; then
  log_err "Run as your regular user, without sudo: ./install_opcua_open62541.sh"
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

BUILD_JOBS=${BUILD_JOBS:-$(nproc)}
if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  log_err "BUILD_JOBS must be a positive integer."
fi

# 1.4 is open62541's maintained LTS branch; override with a release tag if needed.
OPEN62541_REF=${OPEN62541_REF:-1.4}
INSTALL_PREFIX=${INSTALL_PREFIX:-/usr/local}

log_info "Installing open62541 build dependencies for Ubuntu 26.04 (${ARCH})..."
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  ca-certificates \
  cmake \
  git \
  libssl-dev \
  ninja-build \
  pkg-config

BUILD_ROOT=$(mktemp -d)
trap 'rm -rf "$BUILD_ROOT"' EXIT

log_info "Building open62541 ${OPEN62541_REF} with OpenSSL encryption support..."
git clone --depth 1 --branch "$OPEN62541_REF" --recurse-submodules \
  https://github.com/open62541/open62541.git "$BUILD_ROOT/open62541"

cmake -S "$BUILD_ROOT/open62541" -B "$BUILD_ROOT/open62541/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DBUILD_SHARED_LIBS=ON \
  -DUA_ENABLE_ENCRYPTION=OPENSSL \
  -DUA_ENABLE_PUBSUB=ON \
  -DUA_ENABLE_AMALGAMATION=OFF \
  -DUA_BUILD_EXAMPLES=OFF \
  -DUA_BUILD_UNIT_TESTS=OFF
cmake --build "$BUILD_ROOT/open62541/build" --parallel "$BUILD_JOBS"
sudo cmake --install "$BUILD_ROOT/open62541/build"
sudo ldconfig

log_info "Checking installed headers, library, and pkg-config metadata..."
if ! pkg-config --exists open62541; then
  log_err "open62541 installed, but pkg-config cannot find it. Check PKG_CONFIG_PATH for ${INSTALL_PREFIX}."
fi
if [[ ! -f "$INSTALL_PREFIX/include/open62541/server.h" ]]; then
  log_err "Expected header missing: $INSTALL_PREFIX/include/open62541/server.h"
fi
pkg-config --modversion open62541

log_info "open62541 is ready for C/C++ development."
log_info "CMake: find_package(open62541 CONFIG REQUIRED), then link open62541::open62541"
log_info "pkg-config: $(pkg-config --cflags --libs open62541)"
log_warn "No firewall rule or server service was added. Configure certificates, access control, and endpoint exposure in your application before deployment."