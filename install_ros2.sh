#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ "$EUID" -eq 0 ]]; then
  fail "Run this script as your regular user, without sudo."
fi

if [[ ! -r /etc/os-release ]]; then
  fail "Cannot identify the operating system."
fi

. /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
  fail "Unsupported OS: ${PRETTY_NAME:-unknown}. This script supports Ubuntu."
fi

case "${VERSION_ID:-}" in
  22.04) ros_distro="humble" ;;
  24.04) ros_distro="jazzy" ;;
  26.04) ros_distro="lyrical" ;;
  *) fail "Unsupported Ubuntu version: ${VERSION_ID:-unknown}." ;;
esac

codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[[ -n "$codename" ]] || fail "Could not determine the Ubuntu codename."

arch="$(dpkg --print-architecture)"
ros_variant="${ROS_VARIANT:-ros-base}"

case "$arch" in
  amd64|arm64) ;;
  *) fail "Unsupported architecture: $arch. Supported: amd64, arm64." ;;
esac

case "$ros_variant" in
  ros-base|desktop) ;;
  *) fail "Unsupported ROS_VARIANT: $ros_variant. Choose ros-base or desktop." ;;
esac

apt_update() {
  sudo find /var/lib/apt/lists -maxdepth 1 -type f -name '*_Packages' -size 0 -print -delete
  sudo apt-get -o APT::Update::Error-Mode=any update
}

if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
  echo "Installing tools needed to configure the ROS repository..."
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg locales
fi

ros_repo="https://packages.ros.org/ros2/ubuntu"
ros_inrelease="${ros_repo}/dists/${codename}/InRelease"
if ! curl --fail --silent --show-error --output /dev/null "$ros_inrelease"; then
  ros_repo="http://packages.ros.org/ros2/ubuntu"
  ros_inrelease="${ros_repo}/dists/${codename}/InRelease"
  if ! curl --fail --silent --show-error --output /dev/null "$ros_inrelease"; then
    fail "ROS repository is unreachable over HTTPS and HTTP: ${ros_inrelease}"
  fi
  echo "WARNING: HTTPS certificate validation failed. Using HTTP transport; APT will still verify repository signatures with the ROS key."
fi

sudo locale-gen en_US en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

sudo install -m 0755 -d /usr/share/keyrings
curl --fail --silent --show-error \
  https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  | sudo gpg --dearmor --yes -o /usr/share/keyrings/ros-archive-keyring.gpg
sudo chmod a+r /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=${arch} signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] ${ros_repo} ${codename} main" \
  | sudo tee /etc/apt/sources.list.d/ros2.list >/dev/null

echo "Updating Ubuntu and ROS package indexes..."
apt_update

echo "Updating package indexes with the ROS repository..."
sudo apt-get install -y \
  "ros-${ros_distro}-${ros_variant}" \
  python3-rosdep \
  python3-colcon-common-extensions

if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  sudo rosdep init
fi
rosdep update

bashrc="${HOME}/.bashrc"
ros_setup="source /opt/ros/${ros_distro}/setup.bash"
if ! grep -Fqx "$ros_setup" "$bashrc" 2>/dev/null; then
  printf '\n%s\n' "$ros_setup" >> "$bashrc"
fi

echo "Installed ROS 2 ${ros_distro} (${ros_variant})."
echo "Open a new shell or run: ${ros_setup}"

sudo apt update && sudo apt install "ros-${ROS_DISTRO}-rviz2"