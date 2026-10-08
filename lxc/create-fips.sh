#!/bin/bash
#
# Create an Ubuntu VM, attach it to an Ubuntu Pro subscription and enable the
# FIPS-updates stream.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/common.sh"

GUEST_USER=ubuntu

usage() {
	cat <<-EOU
	Usage:
	  ${0##*/} <ubuntu pro token> [name] [series]
	  ${0##*/} -h    show this help

	Defaults: name=fips  series=focal

	Example:
	  ${0##*/} C1xxxxxxxxxxxxxxxx
	EOU
}

case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac

need_cmd lxc jq

PRO_TOKEN="$1"
VM_NAME="${2:-fips}"
SERIES="${3:-focal}"

if instance_exists "$VM_NAME"; then die "instance $VM_NAME already exists"; fi

log "launching VM $VM_NAME (ubuntu:$SERIES)"
lxc launch "ubuntu:$SERIES" "$VM_NAME" --vm \
	-c security.secureboot=false -c limits.cpu=8 -c limits.memory=16GiB

wait_for_path "$VM_NAME" "/home/$GUEST_USER/.ssh"
push_ssh_key "$VM_NAME" "$GUEST_USER"

ADDR=$(wait_for_addr "$VM_NAME")
ssh_config_add "$VM_NAME" "$ADDR" "$GUEST_USER"
check_ssh_agent

# Wait for sshd rather than assuming it is up the moment an address appears.
wait_for 120 "ssh on $VM_NAME" remote_ssh "$VM_NAME" true

log "attaching Ubuntu Pro subscription"
remote_ssh "$VM_NAME" sudo pro attach "$PRO_TOKEN"

log "enabling fips-updates"
remote_ssh "$VM_NAME" sudo pro enable fips-updates --assume-yes

log "$VM_NAME ready; reboot it to run the FIPS kernel:  lxc restart $VM_NAME"
