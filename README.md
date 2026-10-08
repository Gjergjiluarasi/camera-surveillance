# Industrial Robotics & IIoT Ecosystem Setup

This repository contains setup scripts for preparing Ubuntu systems for robotics and industrial IoT development. [setup_ecosystem.sh](setup_ecosystem.sh) installs the general development stack, and [install_ethercat_igh.sh](install_ethercat_igh.sh) builds and configures the IgH EtherCAT Master for Ubuntu 26.04.

The script installs and configures a development environment for:

- Docker and Docker Compose
- ROS 2
- EtherCAT-related tools and networking support
- OPC UA stack via open62541
- MQTT broker with Mosquitto
- Zenoh router
- OpenCV development libraries
- SSH X11 forwarding
- IIoT telemetry stack template with InfluxDB and Grafana
- Real-time diagnostic tools and PlotJuggler

---

## Supported Platforms

The script is intended for Ubuntu systems:

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Ubuntu 26.04 LTS

It supports the following CPU architectures:

- amd64
- arm64

---

## Prerequisites

Before running the script:

- Use a normal user account, not root
- Ensure your user has sudo access
- Have a working internet connection
- Use a machine with a standard Ubuntu desktop/server install

> The script explicitly refuses to run as root and will exit if it detects that you launched it with sudo.

---

## Quick Start

```bash
chmod +x ./setup_ecosystem.sh
./setup_ecosystem.sh
```

The script will automatically:

1. Update package indexes
2. Install base development tools
3. Configure Docker and add your user to the `docker` group
4. Install ROS 2 for the detected Ubuntu version
5. Configure ROS environment variables
6. Build and install open62541
7. Enable Mosquitto
8. Install Zenoh router
9. Install OpenCV
10. Enable SSH X11 forwarding
11. Create a local IIoT telemetry stack in `~/iiot_stack`

### IgH EtherCAT Master on Ubuntu 26.04

The ecosystem script installs EtherCAT-related utilities, but the IgH master and its kernel modules are installed separately. Run the focused installer as a regular user; it uses `sudo` for system changes and prompts for the dedicated EtherCAT NIC:

```bash
chmod +x ./install_ethercat_igh.sh
./install_ethercat_igh.sh
```

You can provide the interface name or MAC address non-interactively with `MASTER0_DEVICE=enp2s0 ./install_ethercat_igh.sh`. The installer builds upstream's maintained `stable-1.6` branch against the running kernel headers, enables the generic NIC driver, installs the systemd service and udev permissions, and configures `/etc/ethercat.conf`. It does not start the master or enable it at boot. Review the configuration and verify the NIC is dedicated before starting it with `sudo systemctl start ethercat`. Log out and back in before using EtherCAT devices as your normal user.

### Standalone OPC UA Stack on Ubuntu 26.04

To install open62541 without running the full ecosystem setup, run:

```bash
chmod +x ./install_opcua_open62541.sh
./install_opcua_open62541.sh
```

The installer builds the maintained open62541 `1.4` branch for amd64 or arm64, with OpenSSL encryption and PubSub enabled, and installs the shared library and development files under `/usr/local`. It installs Ubuntu build dependencies and verifies the headers and pkg-config metadata. Override build parallelism or select a release tag with `BUILD_JOBS=2` or `OPEN62541_REF=v1.4.11`.

The script does not start a server, open port 4840, or create a systemd service. Configure application certificates, security policies, user access, and network exposure before deployment.

### YOLO26n Camera Surveillance

The C++ viewer runs YOLO26n object detection on every frame and displays annotated output. It accepts either a V4L2 camera or a prerecorded video. Video files are decoded with OpenCV's FFmpeg backend and paced to the file's frame rate; CPU inference can take longer than that interval, in which case playback slows rather than skipping inference.

Install OpenCV development files with DNN, video I/O, and GUI support. Export the official YOLO26n model to ONNX with Ultralytics:

```bash
python3 -m pip install ultralytics
yolo export model=yolo26n.pt format=onnx imgsz=640
```

Build and run with either input source:

```bash
g++ -std=c++17 -O2 -Wall -Wextra $(pkg-config --cflags opencv4) \
   pinhole_camera_survaillance.cpp -o pinhole_camera_survaillance \
   $(pkg-config --libs opencv4)

./pinhole_camera_survaillance --model yolo26n.onnx --camera 0
./pinhole_camera_survaillance --model yolo26n.onnx --video /path/to/video.mp4
```

The model is loaded by OpenCV DNN on CPU and is expected to produce end-to-end detections with six values per box: `x1, y1, x2, y2, confidence, class_id`. Press `q` or `Esc` in the window to quit. The model input size is 640 and the confidence threshold is 0.25.

### Cockpit on Ubuntu 26.04

To install Cockpit's web-based server management interface without running the full ecosystem setup:

```bash
chmod +x ./install_cockpit.sh
./install_cockpit.sh
```

The installer uses Ubuntu's `cockpit` package and enables `cockpit.socket`. Once installed, open `https://<server-hostname>:9090/` and sign in with a local Ubuntu account. The script does not modify firewall rules; allow TCP port 9090 only on networks where Cockpit should be reachable.

### Home Assistant Container

To install and start Home Assistant in Docker, run:

```bash
chmod +x ./install_home_assistant.sh
./install_home_assistant.sh
```

The script installs Docker using `install_docker.sh` if Docker is missing, then starts the official stable Home Assistant container. Open `http://<server-hostname>:8123/` to finish setup. Home Assistant uses host networking, restarts automatically, and stores its configuration in `~/homeassistant` by default. Set `HA_CONFIG_DIR=/path/to/config` to choose a different persistent config directory. The container can be monitored with `docker logs -f homeassistant` and stopped with `docker stop homeassistant`.

---

## What the Script Installs

### Docker

Installs the official Docker engine and Compose plugin from Docker's Ubuntu repository.

### ROS 2

Detects the Ubuntu release and selects the matching ROS distribution:

- Ubuntu 22.04 -> ROS 2 Humble
- Ubuntu 24.04 -> ROS 2 Jazzy
- Ubuntu 26.04 -> ROS 2 Lyrical

The script configures the appropriate APT source and sources the environment in `~/.bashrc`.

### OPC UA

Builds and installs the open62541 C library from source into `/usr/local`.

### MQTT

Installs Mosquitto and starts the service.

### Zenoh

Downloads the latest Zenoh standalone binary for the target architecture and installs it as `/usr/local/bin/zenohd`.

### OpenCV

Installs OpenCV development packages and Python bindings.

### X11 Forwarding

Enables SSH X11 forwarding by creating a config snippet in `/etc/ssh/sshd_config.d/90-x11-forwarding.conf`.

### IIoT Stack Template

Creates a Docker Compose file at:

```bash
~/iiot_stack/docker-compose.yml
```

This includes:

- InfluxDB
- Grafana

---

## Important Notes

- After Docker installation, log out and log back in so the `docker` group membership takes effect.
- The script assumes a standard Ubuntu environment with `systemd`.
- Some commands may fail in WSL, containers, or non-systemd minimal environments.
- The script may take a long time to complete because it builds open62541 from source and installs multiple packages.

---

## Troubleshooting

### Script exits with a root-user error

Run it as your normal user:

```bash
./setup_ecosystem.sh
```

Do not use:

```bash
sudo ./setup_ecosystem.sh
```

### Docker permission issues

If `docker` commands still fail after installation:

```bash
newgrp docker
```

or log out and back in.

### ROS dependency issues

If `rosdep` fails, update your package sources and retry:

```bash
sudo apt-get update
rosdep update
```

### Systemd-related commands fail

This script uses `systemctl` for services such as Mosquitto and SSH. If your environment is not running `systemd`, those commands may not work.

---

## Recommended Next Steps

After the script finishes:

1. Reboot or restart your shell session
2. Verify Docker works:
   ```bash
   docker --version
   ```
3. Source ROS in a new shell:
   ```bash
   source /opt/ros/${ROS_DISTRO}/setup.bash
   ```
4. Check the generated local IIoT stack in `~/iiot_stack`

---

## License

This project does not currently declare a license. Use it carefully in your local environment and confirm compliance with your organization’s policies before deploying it in production.
