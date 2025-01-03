#!/bin/bash

function show_usage {
        echo "Usage:"
        echo "./create-one-disk.sh {disk name} {disk size in G} [vm name]"
        echo ""
        echo "example:"
        echo "./create-one-disk.sh test-disk 60"
        echo "./create-one-disk.sh test-disk 60 testvm"
        echo ""
}

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        show_usage
        exit 1
fi

# Create volumes for virtual disk
lxc storage volume create default "$1" size="$2"GiB --type block

# Attach to VM
if ! [ -z "$3" ]; then
    lxc config device add "$3" "$1" disk pool=default source="$1"
fi
