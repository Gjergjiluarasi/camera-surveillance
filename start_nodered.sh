#! /usr/bin/bash

docker run -it -p 1880:1880 -v myNodeREDdata:/data --name mynodered nodered/node-red:latest-minimal
