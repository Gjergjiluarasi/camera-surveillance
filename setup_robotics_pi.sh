#!/usr/bin/env bash
set -Eeuo pipefail

# Raspberry Pi 4 Robotics / IIoT Software Ecosystem Bootstrap
# Target: Ubuntu 24.04/26.04 ARM64 on Raspberry Pi 4
#
# Installs/configures:
#   Docker + Compose
#   ROS 2 (auto-selects Jazzy on 24.04, Lyrical on 26.04 when available)
#   EtherCAT master prerequisites (IgH/EtherLab)
#   OPC UA tools/libs
#   MQTT (Mosquitto + clients)
#   Zenoh
#   OpenCV + GStreamer
#   X11 forwarding
#   C/C++/Python development
#   ros2_control and useful ROS tooling
#   Cyclone DDS
#   CAN/GPIO/I2C/SPI/UART tooling
#   networking/diagnostics
#   time synchronisation groundwork
#   dedicated ROS workspace
#
# IMPORTANT:
# - Review the generated /etc/robotics/setup.env before production use.
# - EtherCAT NIC configuration is intentionally NOT hard-coded because the
#   correct interface depends on the machine (eth0/end0/etc.).
# - Reboot after installation.
#
# Usage:
#   chmod +x setup_robotics_pi.sh
#   sudo ./setup_robotics_pi.sh
#
# Optional:
#   ROS_DISTRO=jazzy sudo -E ./setup_robotics_pi.sh
#   SKIP_DOCKER=1 sudo ./setup_robotics_pi.sh
#   SKIP_ROS=1 sudo ./setup_robotics_pi.sh

log()  { echo -e "\n[+] $*"; }
warn() { echo -e "\n[!] $*" >&2; }
die()  { echo -e "\n[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run with sudo/root: sudo ./setup_robotics_pi.sh"

export DEBIAN_FRONTEND=noninteractive

TARGET_USER="${SUDO_USER:-${USER}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "${TARGET_HOME}" ]] || TARGET_HOME="/home/${TARGET_USER}"

. /etc/os-release
UBUNTU_CODENAME="${VERSION_CODENAME:-unknown}"
ARCH="$(dpkg --print-architecture)"

[[ "$ARCH" == "arm64" ]] || warn "Detected architecture: $ARCH. This script is optimized for ARM64 Raspberry Pi."

log "Detected Ubuntu ${VERSION_ID} (${UBUNTU_CODENAME}), architecture ${ARCH}"

if [[ -z "${ROS_DISTRO:-}" ]]; then
    case "${VERSION_ID}" in
        24.04) ROS_DISTRO="jazzy" ;;
        26.04) ROS_DISTRO="lyrical" ;;
        *)      ROS_DISTRO="jazzy" ;;
    esac
fi

# ---------------------------------------------------------------------------
# Base packages
# ---------------------------------------------------------------------------
log "Installing base development, robotics and diagnostics packages"

apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    software-properties-common \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    git \
    git-lfs \
    vim \
    nano \
    tmux \
    htop \
    btop \
    tree \
    unzip \
    zip \
    rsync \
    jq \
    yq \
    bash-completion \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools \
    python3-wheel \
    python3-colcon-common-extensions \
    python3-vcstool \
    python3-rosdep \
    python3-pytest \
    python3-numpy \
    libeigen3-dev \
    libyaml-cpp-dev \
    libspdlog-dev \
    libboost-all-dev \
    libasio-dev \
    libtinyxml2-dev \
    libxml2-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libgpiod-dev \
    gpiod \
    i2c-tools \
    spi-tools \
    setserial \
    minicom \
    usbutils \
    pciutils \
    udev \
    ethtool \
    iproute2 \
    iputils-ping \
    net-tools \
    dnsutils \
    tcpdump \
    traceroute \
    socat \
    netcat-openbsd \
    openssh-client \
    openssh-server \
    chrony \
    linux-tools-common \
    can-utils \
    v4l-utils \
    ffmpeg \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-libav \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libopencv-dev \
    python3-opencv \
    mosquitto \
    mosquitto-clients \
    libmosquitto-dev \
    libopen62541-dev

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------
if [[ "${SKIP_DOCKER:-0}" != "1" ]]; then
    log "Installing Docker Engine + Compose"

    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker

    if id "$TARGET_USER" >/dev/null 2>&1; then
        usermod -aG docker "$TARGET_USER"
    fi
fi

# ---------------------------------------------------------------------------
# ROS 2
# ---------------------------------------------------------------------------
if [[ "${SKIP_ROS:-0}" != "1" ]]; then
    log "Installing ROS 2 ${ROS_DISTRO}"

    install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /usr/share/keyrings/ros-archive-keyring.gpg ]]; then
        curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
            | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg
    fi

    cat >/etc/apt/sources.list.d/ros2.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main
EOF

    apt-get update

    # Prefer desktop for development if available; otherwise fall back to ros-base.
    if apt-cache show "ros-${ROS_DISTRO}-desktop" >/dev/null 2>&1; then
        apt-get install -y "ros-${ROS_DISTRO}-desktop"
    else
        apt-get install -y "ros-${ROS_DISTRO}-ros-base"
    fi

    apt-get install -y \
        "ros-${ROS_DISTRO}-ros2-control" \
        "ros-${ROS_DISTRO}-ros2-controllers" \
        "ros-${ROS_DISTRO}-controller-manager" \
        "ros-${ROS_DISTRO}-joint-state-publisher" \
        "ros-${ROS_DISTRO}-joint-state-publisher-gui" \
        "ros-${ROS_DISTRO}-robot-state-publisher" \
        "ros-${ROS_DISTRO}-xacro" \
        "ros-${ROS_DISTRO}-tf-transformations" \
        "ros-${ROS_DISTRO}-image-transport" \
        "ros-${ROS_DISTRO}-image-transport-plugins" \
        "ros-${ROS_DISTRO}-cv-bridge" \
        "ros-${ROS_DISTRO}-vision-opencv" \
        "ros-${ROS_DISTRO}-diagnostic-updater" \
        "ros-${ROS_DISTRO}-topic-tools" \
        "ros-${ROS_DISTRO}-rqt" \
        "ros-${ROS_DISTRO}-rqt-common-plugins" \
        "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" \
        "ros-${ROS_DISTRO}-rmw-fastrtps-cpp" \
        "ros-${ROS_DISTRO}-rosbag2" \
        "ros-${ROS_DISTRO}-launch-testing"

    # Initialize rosdep if necessary.
    if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
        rosdep init || true
    fi
    rosdep update || true
fi

# ---------------------------------------------------------------------------
# Zenoh
# ---------------------------------------------------------------------------
log "Installing Zenoh repository and CLI"

if [[ ! -f /etc/apt/keyrings/zenoh-archive-keyring.gpg ]]; then
    curl -fsSL https://download.eclipse.org/zenoh/deb/zenoh-public.key \
        | gpg --dearmor -o /etc/apt/keyrings/zenoh-archive-keyring.gpg || true
fi

if [[ -f /etc/apt/keyrings/zenoh-archive-keyring.gpg ]]; then
    cat >/etc/apt/sources.list.d/zenoh.list <<EOF
deb [signed-by=/etc/apt/keyrings/zenoh-archive-keyring.gpg] https://download.eclipse.org/zenoh/deb/ /
EOF
    apt-get update || true
    apt-get install -y zenoh zenohd 2>/dev/null || true
else
    warn "Zenoh APT repository was not available; install zenoh/zenohd separately if required."
fi

# ---------------------------------------------------------------------------
# EtherCAT / IgH prerequisites
# ---------------------------------------------------------------------------
log "Preparing EtherCAT / IgH EtherCAT Master environment"

apt-get install -y \
    autoconf \
    automake \
    libtool \
    flex \
    bison \
    libreadline-dev \
    linux-headers-"$(uname -r)" 2>/dev/null || true

# Try Ubuntu packages where available.
apt-get install -y ethercat ethercat-master 2>/dev/null || true

mkdir -p /etc/ethercat

cat >/etc/ethercat/README.md <<'EOF'
EtherCAT configuration
======================

The correct EtherCAT interface must be selected for this machine.

Find interfaces:
    ip -br link
    ethtool -i eth0

For IgH/EtherLab, configure the master and MAC/interface according to
the installed master version.

Do NOT blindly assign the normal LAN interface to EtherCAT if the same
interface is also used for SSH/network traffic.

For hard real-time EtherCAT:
- Prefer a dedicated Ethernet NIC/port.
- Use a PREEMPT_RT kernel when your timing requirements justify it.
- Disable power-saving features that introduce unacceptable jitter.
- Measure latency/jitter under load before connecting actuators.
EOF

# ---------------------------------------------------------------------------
# OPC UA
# ---------------------------------------------------------------------------
log "Preparing OPC UA development environment"

apt-get install -y libopen62541-dev 2>/dev/null || true

mkdir -p /opt/robotics/examples/opcua
cat >/opt/robotics/examples/opcua/README.md <<'EOF'
OPC UA
======

C/C++:
  open62541 development headers/libraries are installed when available.

Python:
  create a virtual environment and install:
      python3 -m venv ~/venvs/opcua
      ~/venvs/opcua/bin/pip install asyncua

Use OPC UA primarily for industrial information exchange/configuration.
For hard real-time motion loops, keep the control path local/real-time.
EOF

# ---------------------------------------------------------------------------
# MQTT
# ---------------------------------------------------------------------------
log "Enabling MQTT broker"

systemctl enable mosquitto
systemctl start mosquitto

# Do not expose MQTT remotely by default. Localhost-only is safer until
# authentication/TLS/network policy has been explicitly configured.
mkdir -p /etc/mosquitto/conf.d
cat >/etc/mosquitto/conf.d/robotics-local.conf <<'EOF'
# Local robotics development defaults.
# Remote access should be explicitly configured with authentication and TLS.
listener 1883 127.0.0.1
allow_anonymous true
EOF

systemctl restart mosquitto

# ---------------------------------------------------------------------------
# X11 / GUI forwarding
# ---------------------------------------------------------------------------
log "Configuring X11 forwarding support"

apt-get install -y \
    xauth \
    x11-apps \
    x11-utils \
    mesa-utils \
    libgl1-mesa-dri \
    libglx-mesa0

mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/robotics-x11.conf <<'EOF'
X11Forwarding yes
X11UseLocalhost yes
EOF

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

# ---------------------------------------------------------------------------
# User groups / hardware access
# ---------------------------------------------------------------------------
log "Configuring hardware-access groups"

for group in dialout i2c spi gpio video render input plugdev; do
    if getent group "$group" >/dev/null 2>&1; then
        usermod -aG "$group" "$TARGET_USER" || true
    fi
done

# ---------------------------------------------------------------------------
# Robotics directories
# ---------------------------------------------------------------------------
log "Creating robotics workspace and configuration"

mkdir -p \
    /opt/robotics \
    /opt/robotics/bin \
    /opt/robotics/config \
    /opt/robotics/examples \
    /opt/robotics/logs \
    /opt/robotics/docker \
    "${TARGET_HOME}/robot_ws/src"

chown -R "$TARGET_USER:$TARGET_USER" \
    /opt/robotics \
    "${TARGET_HOME}/robot_ws"

# Environment file
cat >/etc/robotics.env <<EOF
# Robotics machine environment
export ROS_DISTRO="${ROS_DISTRO}"
export ROS_DOMAIN_ID=0
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# Useful ROS defaults
export RCUTILS_COLORIZED_OUTPUT=1
export RCUTILS_LOGGING_BUFFERED_STREAM=1

# Docker
export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1

# Camera/OpenCV/GStreamer
export GST_DEBUG=1

# Zenoh
export ZENOH_ROUTER_CONFIG=/opt/robotics/config/zenohd.json5
EOF

cat >/etc/robotics/setup.bash <<'EOF'
#!/usr/bin/env bash

if [[ -f /etc/robotics.env ]]; then
    source /etc/robotics.env
fi

if [[ -n "${ROS_DISTRO:-}" && -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
fi

if [[ -f "${HOME}/robot_ws/install/setup.bash" ]]; then
    source "${HOME}/robot_ws/install/setup.bash"
fi
EOF

chmod +x /etc/robotics/setup.bash

# Add to interactive shell for the target user.
cat >/etc/profile.d/robotics.sh <<'EOF'
# Robotics development environment
if [[ -f /etc/robotics/setup.bash ]]; then
    source /etc/robotics/setup.bash
fi
EOF

# Also create user-local bash hook.
touch "${TARGET_HOME}/.bashrc"
grep -qF 'source /etc/robotics/setup.bash' "${TARGET_HOME}/.bashrc" || \
    echo 'source /etc/robotics/setup.bash' >> "${TARGET_HOME}/.bashrc"
chown "$TARGET_USER:$TARGET_USER" "${TARGET_HOME}/.bashrc"

# ---------------------------------------------------------------------------
# Cyclone DDS basic configuration
# ---------------------------------------------------------------------------
cat >/opt/robotics/config/cyclonedds.xml <<'EOF'
<?xml version="1.0"?>
<CycloneDDS xmlns="https://cdds.io/config">
  <Domain id="any">
    <General>
      <AllowMulticast>true</AllowMulticast>
    </General>
    <Tracing>
      <Verbosity>warning</Verbosity>
    </Tracing>
  </Domain>
</CycloneDDS>
EOF

# ---------------------------------------------------------------------------
# Zenoh basic configuration
# ---------------------------------------------------------------------------
cat >/opt/robotics/config/zenohd.json5 <<'EOF'
{
  mode: "router",
  listen: {
    endpoints: [
      "tcp/0.0.0.0:7447"
    ]
  }
}
EOF

# ---------------------------------------------------------------------------
# Docker Compose robotics development container
# ---------------------------------------------------------------------------
cat >/opt/robotics/docker/compose.yaml <<EOF
services:
  robotics-dev:
    image: ros:${ROS_DISTRO}-ros-base
    container_name: robotics-dev
    network_mode: host
    privileged: true
    ipc: host
    pid: host
    environment:
      - ROS_DOMAIN_ID=0
      - RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
      - DISPLAY=\${DISPLAY:-:0}
      - QT_X11_NO_MITSHM=1
    volumes:
      - /tmp/.X11-unix:/tmp/.X11-unix:rw
      - ${TARGET_HOME}/robot_ws:/workspace/robot_ws
      - /dev:/dev
      - /opt/robotics/config:/opt/robotics/config:ro
    stdin_open: true
    tty: true
EOF

chown -R "$TARGET_USER:$TARGET_USER" /opt/robotics

# ---------------------------------------------------------------------------
# Useful diagnostic script
# ---------------------------------------------------------------------------
cat >/opt/robotics/bin/robotics-status <<'EOF'
#!/usr/bin/env bash
set +e

echo "========== SYSTEM =========="
uname -a
echo
cat /etc/os-release | grep -E '^(PRETTY_NAME|VERSION_ID)='
echo
echo "========== NETWORK =========="
ip -br addr
echo
echo "========== ETHERNET =========="
for i in /sys/class/net/*; do
    IFACE=$(basename "$i")
    echo "--- $IFACE ---"
    ethtool -i "$IFACE" 2>/dev/null | head -n 8
done
echo
echo "========== DOCKER =========="
docker --version 2>/dev/null
docker compose version 2>/dev/null
echo
echo "========== ROS 2 =========="
if command -v ros2 >/dev/null 2>&1; then
    ros2 --version 2>/dev/null || true
    ros2 doctor --report 2>/dev/null | head -n 60
else
    echo "ros2 not available in current shell"
fi
echo
echo "========== MQTT =========="
systemctl is-active mosquitto
echo
echo "========== ETHERCAT =========="
lsmod | grep -i ethercat || true
echo
echo "========== CAMERAS =========="
v4l2-ctl --list-devices 2>/dev/null || true
echo
echo "========== I2C =========="
i2cdetect -l 2>/dev/null || true
echo
echo "========== CAN =========="
ip -details link show type can 2>/dev/null || true
echo
echo "========== TIME =========="
timedatectl status | head -n 15
echo
echo "========== CPU =========="
nproc
lscpu | grep -E 'Model name|CPU MHz|Architecture' | head -n 5
EOF

chmod +x /opt/robotics/bin/robotics-status

# ---------------------------------------------------------------------------
# Docker test
# ---------------------------------------------------------------------------
if [[ "${SKIP_DOCKER:-0}" != "1" ]]; then
    log "Testing Docker"
    docker run --rm hello-world >/dev/null 2>&1 || warn "Docker test failed; inspect: systemctl status docker"
fi

# ---------------------------------------------------------------------------
# Final
# ---------------------------------------------------------------------------
log "Installation completed."

cat <<EOF

=====================================================================
 ROBOTICS / IIOT SOFTWARE ECOSYSTEM READY
=====================================================================

Ubuntu:
  ${VERSION_ID} ${UBUNTU_CODENAME}
Architecture:
  ${ARCH}

ROS 2:
  ${ROS_DISTRO}

Workspace:
  ${TARGET_HOME}/robot_ws

Global robotics environment:
  /etc/robotics/setup.bash
  /etc/robotics.env

Docker Compose:
  /opt/robotics/docker/compose.yaml

Diagnostics:
  /opt/robotics/bin/robotics-status

Installed/Prepared:
  Docker + Compose
  ROS 2
  ros2_control
  Cyclone DDS
  EtherCAT prerequisites
  OPC UA (open62541)
  MQTT / Mosquitto
  Zenoh
  OpenCV
  GStreamer
  X11 forwarding
  CAN tools
  GPIO / I2C / SPI / UART tools
  network diagnostics
  chrony
  C/C++ + Python development

IMPORTANT:
  1. Reboot before serious hardware testing.
  2. Configure a DEDICATED EtherCAT Ethernet interface.
  3. Do not put EtherCAT traffic through Wi-Fi.
  4. For deterministic motion control, evaluate PREEMPT_RT and
     measure worst-case latency/jitter on the actual workload.
  5. MQTT is currently localhost-only.
  6. Zenoh is configured to listen on TCP/7447; add firewall/authentication
     before exposing it beyond a trusted LAN.
  7. Docker containers using EtherCAT normally require host networking
     and elevated privileges/device access; apply least privilege before
     production deployment.

After reboot:
  source /etc/robotics/setup.bash
  /opt/robotics/bin/robotics-status

=====================================================================
EOF
