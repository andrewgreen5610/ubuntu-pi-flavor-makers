#!/usr/bin/env bash

set -x

if [ -f build-settings.sh ]; then
    source build-settings.sh
else
    echo "ERROR! Could not source build-settings.sh."
    exit 1
fi

if [ $(id -u) -ne 0 ]; then
    echo "ERROR! Must be root."
    exit 1
fi

function nspawn_x11() {
    # Create basic resolv.conf for bind mounting inside the container
    echo "nameserver 1.1.1.1" > ${BASEDIR}/resolv.conf

    # Make sure the container has a machine-id
    systemd-machine-id-setup --root ${DEVICE_R}

    xhost +local:
    # Bind mount resolv.conf and the firmware, set the hostname and spawn
    systemd-nspawn \
      --resolv-conf=off \
      --bind-ro=${BASEDIR}/resolv.conf:/etc/resolv.conf \
      --bind-ro=/home/${SUDO_USER}/.Xauthority:/home/${SUDO_USER}/.Xauthority \
      --bind=${DEVICE_R}/boot/firmware:/boot/firmware \
      --bind=/etc/machine-id \
      --bind=/run/user/1000/pulse:/run/user/host/pulse \
      --bind=/tmp/.X11-unix \
      --setenv=DISPLAY=${DISPLAY} \
      --hostname=${FLAVOUR} \
      --as-pid2 \
      -D ${DEVICE_R} "$@"
    xhost -
    echo '' > ${DEVICE_R}/etc/machine-id
}

if [ -d "${DEVICE_R}" ]; then
    nspawn_x11 "$@"
fi