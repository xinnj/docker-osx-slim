#!/bin/bash
set -e

base=`dirname $0`
if [[ "$#" -lt "1" ]]; then
    echo "Usage: `basename $0` <image file> [shared path]"
    exit 1
fi

imageFile=$1

sharedPath=""
if [[ ! -z "$2" ]]; then
    sharedPath="-v $2:/mnt/hostshare -e HOST_SHARE=/mnt/hostshare"
fi

xhost +

podman run -d --name osx-vm --rm \
    --privileged \
    --device /dev/kvm \
    -v "${imageFile}:/image" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -e "DISPLAY=${DISPLAY:-:0.0}" \
    -e RAM=6 \
    ${sharedPath} \
    -e GENERATE_UNIQUE=false \
    docker.io/xinnj/docker-osx-slim
