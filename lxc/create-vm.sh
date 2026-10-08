#!/bin/bash
#
# Create an Ubuntu LXD virtual machine, install our ssh key and add an
# ~/.ssh/config entry for it.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/common.sh"

GUEST_USER=ubuntu

usage() {
	cat <<-EOU
	Usage:
	  ${0##*/} <series> <name> <cpus> <memory GB> <disk GB> <create storage: yes|no> <from daily: yes|no>
	  ${0##*/} -h    show this help

	Example:
	  ${0##*/} noble noble-vm 4 8 60 yes no

	List available images with:  lxc image list ubuntu:   /   lxc image list ubuntu-daily:
	EOU
}

need_cmd lxc jq

case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
[ "$#" -eq 7 ] || { echo "error: expected 7 arguments, got $#" >&2; usage; exit 1; }

SERIES="$1"
VM_NAME="$2"
CPUS="$3"
MEM="$4"
DISK="$5"
CREATE_DISK="$6"
DAILY_BUILD="$7"

for n in "$CPUS" "$MEM" "$DISK"; do
	[[ "$n" =~ ^[0-9]+$ ]] || die "cpus, memory and disk must be numbers, got '$n'"
done
[ "$CREATE_DISK" = "yes" ] || [ "$CREATE_DISK" = "no" ] || die "create storage must be yes or no"
[ "$DAILY_BUILD" = "yes" ] || [ "$DAILY_BUILD" = "no" ] || die "from daily must be yes or no"
if instance_exists "$VM_NAME"; then die "instance $VM_NAME already exists"; fi

init_args=()
if [ "$CREATE_DISK" = "yes" ]; then
	log "creating storage pool $VM_NAME-disk (dir)"
	lxc storage create "$VM_NAME-disk" dir || die "create storage failed"
	init_args+=(--storage "$VM_NAME-disk")
fi

if [ "$DAILY_BUILD" = "yes" ]; then IMAGE="ubuntu-daily:$SERIES"; else IMAGE="ubuntu:$SERIES"; fi

log "initialising VM $VM_NAME from $IMAGE"
lxc init "$IMAGE" "$VM_NAME" --vm "${init_args[@]}" || die "init $VM_NAME failed"

lxc config set "$VM_NAME" limits.cpu "$CPUS"
lxc config set "$VM_NAME" limits.memory "${MEM}GiB"
lxc config set "$VM_NAME" security.secureboot false
# Old LXD spells this "lxc config device set"; "override" is needed once the
# root device is inherited from the profile rather than defined on the instance.
lxc config device override "$VM_NAME" root size="${DISK}GiB"

log "starting VM $VM_NAME"
lxc start "$VM_NAME"

wait_for_path "$VM_NAME" "/home/$GUEST_USER/.ssh"
push_ssh_key "$VM_NAME" "$GUEST_USER"

ADDR=$(wait_for_addr "$VM_NAME")
ssh_config_add "$VM_NAME" "$ADDR" "$GUEST_USER"
check_ssh_agent

log "VM $VM_NAME ready:  ssh $VM_NAME"
