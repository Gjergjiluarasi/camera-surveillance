#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as your regular user, without sudo."
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  if [[ ! -x "${script_dir}/install_docker.sh" ]]; then
    echo "Docker is not installed and install_docker.sh is unavailable."
    exit 1
  fi
  "${script_dir}/install_docker.sh"
fi

docker_cmd=(docker)
if ! docker info >/dev/null 2>&1; then
  if ! command -v sudo >/dev/null 2>&1 || ! sudo docker info >/dev/null 2>&1; then
    echo "Cannot access the Docker daemon. Check that Docker is running and that your user has permission."
    echo "After adding your user to the docker group, log out and back in."
    exit 1
  fi
  docker_cmd=(sudo docker)
fi

config_dir="${HA_CONFIG_DIR:-${HOME}/homeassistant}"
mkdir -p "${config_dir}"

if "${docker_cmd[@]}" container inspect homeassistant >/dev/null 2>&1 \
  && "${docker_cmd[@]}" port homeassistant 8123/tcp 2>/dev/null | grep -Fq '0.0.0.0:8123'; then
  "${docker_cmd[@]}" start homeassistant >/dev/null
  echo "Started existing Home Assistant container."
else
  if "${docker_cmd[@]}" container inspect homeassistant >/dev/null 2>&1; then
    "${docker_cmd[@]}" rm --force homeassistant >/dev/null
  fi
  "${docker_cmd[@]}" run -d \
    --name homeassistant \
    --restart unless-stopped \
    --publish 8123:8123 \
    --volume "${config_dir}:/config" \
    --volume /etc/localtime:/etc/localtime:ro \
    --init \
    ghcr.io/home-assistant/home-assistant:stable
  echo "Started Home Assistant container."
fi

echo "Open http://localhost:8123/ to finish setup."
echo "Configuration is stored in: ${config_dir}"
echo "Manage it with: ${docker_cmd[*]} logs -f homeassistant"
