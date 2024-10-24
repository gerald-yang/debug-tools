#!/bin/bash

# Create a pool for disks
lxc storage create bcache zfs size=60GB

# Create volumes for virtual disk
lxc storage volume create bcache backing1 size=20GiB --type block
lxc storage volume create bcache backing2 size=20GiB --type block
lxc storage volume create bcache cache size=10GiB --type block

# Attach to VM
lxc config device add jammy-kvm backing1 disk pool=bcache source=backing1
lxc config device add jammy-kvm backing2 disk pool=bcache source=backing2
lxc config device add jammy-kvm cache disk pool=bcache source=cache

# Remove disk from VM
# lxc config device remove jammy-kvm backing1
# lxc config device remove jammy-kvm backing2
# lxc config device remove jammy-kvm cache
#
# Remove volume
# lxc storage volume delete bcache backing1
# lxc storage volume delete bcache backing2
# lxc storage volume delete bcache cache
