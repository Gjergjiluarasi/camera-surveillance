#! /usr/bin/bash
sudo apt update
sudo apt install -y libopencv-dev pkg-config
sudo dpkg --configure -a
pkg-config --modversion opencv4
pkg-config --cflags opencv4
g++ -std=c++17 -O2 -Wall -Wextra $(pkg-config --cflags opencv4) \
   pinhole_camera_survaillance.cpp -o pinhole_camera_survaillance \
   $(pkg-config --libs opencv4)
