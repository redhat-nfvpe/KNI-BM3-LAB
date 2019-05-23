#!/usr/bin/env bash
set -xe

IMAGE_DIR="/home/libvirt/images"

sudo mkdir -p "$IMAGE_DIR"
parent=$(dirname "$IMAGE_DIR")
sudo chown -R qemu.qemu "$parent"

sudo rm -rf /var/lib/libvirt/images
sudo ln -s "$IMAGE_DIR" /var/lib/libvirt/images

sudo chown -h qemu:qemu /var/lib/libvirt/images

