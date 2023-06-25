#!/bin/bash
set -e

base=`dirname $0`
if [[ "$#" -lt "1" ]]; then
    echo "Usage: `basename $0` <image file> [shared path]"
    exit 1
fi

imageFile=$1

sharedPath=""
SharedPathCmd=""
if [[ ! -z "$2" ]]; then
    sharedPath="-v $2:/mnt/hostshare -e HOST_SHARE=/mnt/hostshare"
    SharedPathCmd="sudo -S mount_9p hostshare &&"
fi

podman run -d --name osx-vm --rm \
    --privileged \
    --device /dev/kvm \
    -v "${imageFile}:/image" \
    -e RAM=6 \
    -e HEADLESS=true \
    -e OSX_COMMANDS="/bin/bash -c \"${SharedPathCmd} ioreg -l | grep IOPlatformSerialNumber && while :; do echo '.'; sleep 5 ; done\"" \
    ${sharedPath} \
    -e GENERATE_UNIQUE=false \
    docker.io/xinnj/docker-osx-slim