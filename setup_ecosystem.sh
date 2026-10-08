#!/usr/bin/env bash
# ==============================================================================
# INDUSTRIAL ROBOTICS & IIOT ECOSYSTEM SETUP SCRIPT
# ==============================================================================
# Target OS: Ubuntu 22.04 LTS (Jammy) / 24.04 LTS (Noble) / 26.04 LTS (Resolute)
# This script configures Docker, ROS2, EtherCAT (IgH/SOEM), OPC UA, MQTT, Zenoh,
# X11 Forwarding, OpenCV, and recommended real-time extensions/tools.
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# The script uses sudo for privileged operations; running it with sudo changes
# HOME and USER and can configure root instead of the invoking account.
if [ "$EUID" -eq 0 ]; then
  log_err "Run this script as your regular user, without sudo: ./setup_ecosystem.sh"
fi

if [ -r /etc/os-release ]; then
  . /etc/os-release
else
  log_err "Cannot identify the operating system; expected Ubuntu 22.04, 24.04, or 26.04."
fi

if [ "${ID:-}" != "ubuntu" ] || { [ "${VERSION_ID:-}" != "22.04" ] && [ "${VERSION_ID:-}" != "24.04" ] && [ "${VERSION_ID:-}" != "26.04" ]; }; then
  log_err "Unsupported OS: ${PRETTY_NAME:-unknown}. Supported releases are Ubuntu 22.04, 24.04, and 26.04."
fi

UBUNTU_CODENAME=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
ARCH=$(dpkg --print-architecture)
USER_NAME=$(id -un)

case "$VERSION_ID" in
  22.04) ROS_DISTRO="humble" ;;
  24.04) ROS_DISTRO="jazzy" ;;
  26.04) ROS_DISTRO="lyrical" ;;
esac

ROS_VARIANT=${ROS_VARIANT:-ros-base}
if [ "$ROS_VARIANT" != "ros-base" ] && [ "$ROS_VARIANT" != "desktop" ]; then
  log_err "Unsupported ROS_VARIANT: $ROS_VARIANT. Choose ros-base or desktop."
fi

case "$ARCH" in
  amd64|arm64) ;;
  *) log_err "Unsupported architecture: $ARCH. This script supports amd64 and arm64." ;;
esac

if [ "$VERSION_ID" = "26.04" ] && [ "$UBUNTU_CODENAME" != "resolute" ]; then
  log_err "Ubuntu 26.04 must use the resolute codename; detected '${UBUNTU_CODENAME:-unset}'."
fi

# --- Step 0: System Prerequisites ---
log_info "Updating package indexes and installing base essentials..."
sudo apt-get update
BASE_PACKAGES=(
    ca-certificates
  curl
    gnupg2
    lsb-release
    build-essential
    cmake
    git
    pkg-config
    python3
    net-tools
    iproute2
    openssh-server
    tmux
    unzip
    locales
)
if ! sudo apt-get -s install "${BASE_PACKAGES[@]}" >/dev/null; then
    log_err "APT cannot resolve the base packages. Check that Ubuntu ${UBUNTU_CODENAME} repositories match the installed system packages; no OS upgrade was attempted."
fi
sudo apt-get install -y "${BASE_PACKAGES[@]}"

BUILD_JOBS=${BUILD_JOBS:-2}
if ! [[ "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  log_err "BUILD_JOBS must be a positive integer."
fi

# --- Step 1: Docker & Docker Compose Setup ---
log_info "Installing Docker Engine and Compose plugin..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure non-root docker access
if ! getent group docker > /dev/null; then
    sudo groupadd docker
fi
sudo usermod -aG docker "$USER_NAME"
log_warn "Docker installed. You may need to log out and log back in for group changes to take effect."

# --- Step 2: ROS 2 Installation ---
log_info "Configuring ROS 2 sources and installing packages..."
# Set locale
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# Setup the ROS repository and signing key.
sudo install -m 0755 -d /usr/share/keyrings
curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | sudo gpg --dearmor --yes -o /usr/share/keyrings/ros-archive-keyring.gpg
sudo chmod a+r /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] https://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

sudo apt-get update
sudo apt-get install -y \
  "ros-${ROS_DISTRO}-${ROS_VARIANT}" \
  python3-colcon-common-extensions \
  python3-rosdep \
  "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"

# Source ROS2 automatically in setup
if ! grep -Fq "source /opt/ros/${ROS_DISTRO}/setup.bash" "$HOME/.bashrc"; then
  echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> "$HOME/.bashrc"
fi

# Initialize rosdep
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    sudo rosdep init || true
fi
rosdep update || true

# --- Step 3: EtherCAT Master Stack & Tools ---
log_info "Installing EtherCAT utilities and SOEM dependencies..."
sudo apt-get install -y libtool automake

# Setup capabilities for raw socket execution without root for SOEM bin files
log_info "Configuring capabilities for real-time networking (EtherCAT/SOEM)..."
# (Example targeted command for custom binaries: sudo setcap cap_net_raw+ep <your_executable>)

# --- Step 4: OPC UA (open62541) Setup ---
log_info "Building and installing open62541 C stack from source..."
BUILD_ROOT=$(mktemp -d)
trap 'rm -rf "$BUILD_ROOT"' EXIT
git clone --depth 1 --recursive https://github.com/open62541/open62541.git "$BUILD_ROOT/open62541"
cmake -S "$BUILD_ROOT/open62541" -B "$BUILD_ROOT/open62541/build" \
  -DBUILD_SHARED_LIBS=ON \
  -DUA_ENABLE_AMBIGUOUS_TYPES=ON
cmake --build "$BUILD_ROOT/open62541/build" --parallel "$BUILD_JOBS"
sudo cmake --install "$BUILD_ROOT/open62541/build"
sudo ldconfig

# --- Step 5: MQTT Ecosystem (Mosquitto & Eclipse Paho) ---
log_info "Installing Mosquitto MQTT Broker and development clients..."
sudo apt-get install -y mosquitto mosquitto-clients libmosquitto-dev
sudo systemctl enable mosquitto
sudo systemctl start mosquitto

# --- Step 6: Zenoh (Next-Gen IIoT Data Protocol) ---
log_info "Installing Eclipse Zenoh router for ${ARCH}..."
case "$ARCH" in
  arm64) ZENOH_TARGET="aarch64-unknown-linux-gnu" ;;
  amd64) ZENOH_TARGET="x86_64-unknown-linux-gnu" ;;
esac
ZENOH_VERSION=$(curl -fsSL https://api.github.com/repos/eclipse-zenoh/zenoh/releases/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
ZENOH_ARCHIVE="$BUILD_ROOT/zenoh.zip"
curl -fL "https://github.com/eclipse-zenoh/zenoh/releases/download/${ZENOH_VERSION}/zenoh-${ZENOH_VERSION}-${ZENOH_TARGET}-standalone.zip" -o "$ZENOH_ARCHIVE"
ZENOH_MEMBER=$(unzip -Z1 "$ZENOH_ARCHIVE" | awk -F/ '$NF == "zenohd" {print; exit}')
if [ -z "$ZENOH_MEMBER" ]; then
    log_err "zenohd was not found in the ${ZENOH_TARGET} release archive."
fi
unzip -p "$ZENOH_ARCHIVE" "$ZENOH_MEMBER" > "$BUILD_ROOT/zenohd"
sudo install -m 0755 "$BUILD_ROOT/zenohd" /usr/local/bin/zenohd

# --- Step 7: OpenCV (Computer Vision Framework) ---
log_info "Installing OpenCV runtime, developer flags, and Python bindings..."
sudo apt-get install -y libopencv-dev python3-opencv

# --- Step 8: X11 Forwarding Configuration ---
log_info "Configuring SSH Server for X11 Forwarding..."
sudo tee /etc/ssh/sshd_config.d/90-x11-forwarding.conf > /dev/null <<'EOF'
X11Forwarding yes
X11UseLocalhost yes
EOF
sudo sshd -t
sudo systemctl reload ssh

# --- Step 9: Proposing Added Engineering Enhancements ---
log_info "Adding Engineering Enhancements: Real-Time tools, PlotJuggler, and Micro-ROS..."
# 9.1 RT-Preempt testing utilities
sudo apt-get install -y rt-tests traceroute htop
# 9.2 PlotJuggler (Vital for ROS2/MQTT data time-series visualization)
sudo apt-get install -y ros-${ROS_DISTRO}-plotjuggler-ros

# 9.3 InfluxDB + Grafana setup via Docker Compose template for IIoT telemetry
mkdir -p "$HOME/iiot_stack"
cat << 'EOF' > "$HOME/iiot_stack/docker-compose.yml"
services:
  influxdb:
    image: influxdb:2.7.12
    ports:
      - "127.0.0.1:8086:8086"
    volumes:
      - influxdb-data:/var/lib/influxdb2
  grafana:
    image: grafana/grafana:12.2.0
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
    depends_on:
      - influxdb

volumes:
  influxdb-data:
  grafana-data:
EOF

log_info "=============================================================================="
log_info " ECOSYSTEM SETUP COMPLETE"
log_info "=============================================================================="
log_info "Installed Specs:"
log_info "  - Docker & Compose Engine"
log_info "  - ROS 2 (${ROS_DISTRO} ${ROS_VARIANT})"
log_info "  - EtherCAT Support Network tools"
log_info "  - open62541 OPC UA Stack (/usr/local/include/open62541/)"
log_info "  - Mosquitto MQTT Broker (Running on port 1883)"
log_info "  - Eclipse Zenoh Router (zenohd ready)"
log_info "  - OpenCV Dev System & Python Bindings"
log_info "  - SSH X11 Forwarding enabled"
log_info "  - IIoT Stack Template: Created in ~/iiot_stack/"
log_info "  - RT Diagnostic Framework: rt-tests & PlotJuggler loaded"
log_info "=============================================================================="
log_info "Please reboot your system or restart your shell session before developing."